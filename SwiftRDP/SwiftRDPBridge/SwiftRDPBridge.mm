#import "SwiftRDPBridge.h"
#import <AppKit/AppKit.h>
#include <freerdp/freerdp.h>
#include <freerdp/client.h>
#include <freerdp/client/cmdline.h>
#include <freerdp/client/cliprdr.h>
#include <freerdp/channels/cliprdr.h>
#include <freerdp/channels/rdpgfx.h>
#include <freerdp/settings.h>
#include <freerdp/input.h>
#include <freerdp/scancode.h>
#include <freerdp/gdi/gdi.h>
#include <freerdp/gdi/gfx.h>
#include <winpr/input.h>
#include <winpr/user.h>
#include <dispatch/dispatch.h>
#include <inttypes.h>

typedef struct
{
    rdpClientContext common;
    void* bridge;
    pEndPaint originalEndPaint;
    CliprdrClientContext* cliprdr;
    UINT32 requestedClipboardFormat;
    NSInteger lastPasteboardChangeCount;
    NSTimeInterval lastClipboardPollTime;
    CFStringRef cachedPasteboardString;
    NSInteger cachedPasteboardChangeCount;
    BOOL pasteboardPollPending;
    UINT32 requestedWidth;
    UINT32 requestedHeight;
    UINT32 requestedColorDepth;
    BOOL enableRemoteFx;
    BOOL enableAudioPlayback;
    BOOL hasSharedFolder;
} SwiftRDPContext;

static SwiftRDPBridge* bridge_from_context(rdpContext* context) {
    if (!context) return nil;
    return (__bridge SwiftRDPBridge*)((SwiftRDPContext*)context)->bridge;
}

static BOOL my_AuthenticateEx(freerdp* instance, char** username, char** password, char** domain, rdp_auth_reason reason) {
    printf("AuthenticateEx called (reason: %d)\n", reason);
    return password && *password && strlen(*password) > 0;
}

static NSString* cached_pasteboard_string(SwiftRDPContext* context) {
    if (!context) {
        return nil;
    }

    @synchronized([SwiftRDPBridge class]) {
        return [(__bridge NSString*)context->cachedPasteboardString copy];
    }
}

static NSInteger cached_pasteboard_change_count(SwiftRDPContext* context) {
    if (!context) {
        return -1;
    }

    @synchronized([SwiftRDPBridge class]) {
        return context->cachedPasteboardChangeCount;
    }
}

static void update_cached_pasteboard(SwiftRDPContext* context, NSString* string, NSInteger changeCount) {
    if (!context) {
        return;
    }

    @synchronized([SwiftRDPBridge class]) {
        if (context->cachedPasteboardString) {
            CFRelease(context->cachedPasteboardString);
            context->cachedPasteboardString = NULL;
        }
        if (string) {
            context->cachedPasteboardString = (__bridge_retained CFStringRef)[string copy];
        }
        context->cachedPasteboardChangeCount = changeCount;
        context->pasteboardPollPending = FALSE;
    }
}

static void set_pasteboard_string(CliprdrClientContext* cliprdr, NSString* string) {
    if (!string) {
        return;
    }

    NSString* copied = [string copy];
    SwiftRDPContext* context = cliprdr && cliprdr->custom ? (SwiftRDPContext*)cliprdr->custom : NULL;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSPasteboard* pasteboard = [NSPasteboard generalPasteboard];
        [pasteboard clearContents];
        [pasteboard setString:copied forType:NSPasteboardTypeString];
        NSInteger changeCount = [pasteboard changeCount];
        if (context) {
            update_cached_pasteboard(context, copied, changeCount);
            @synchronized([SwiftRDPBridge class]) {
                context->lastPasteboardChangeCount = changeCount;
            }
        }
    });
}

static NSData* clipboard_data_for_format(NSString* string, UINT32 formatId) {
    if (!string) {
        return nil;
    }

    NSMutableData* data = nil;
    if (formatId == CF_UNICODETEXT) {
        data = [[string dataUsingEncoding:NSUTF16LittleEndianStringEncoding] mutableCopy];
        uint16_t terminator = 0;
        [data appendBytes:&terminator length:sizeof(terminator)];
        return data;
    }

    if (formatId == CF_TEXT) {
        data = [[string dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
        uint8_t terminator = 0;
        [data appendBytes:&terminator length:sizeof(terminator)];
        return data;
    }

    return nil;
}

static NSString* string_from_clipboard_data(const BYTE* bytes, UINT32 length, UINT32 formatId) {
    if (!bytes || length == 0) {
        return nil;
    }

    NSUInteger actualLength = length;
    NSStringEncoding encoding = NSUTF8StringEncoding;

    if (formatId == CF_UNICODETEXT) {
        encoding = NSUTF16LittleEndianStringEncoding;
        while (actualLength >= 2 && bytes[actualLength - 1] == 0 && bytes[actualLength - 2] == 0) {
            actualLength -= 2;
        }
    } else {
        while (actualLength > 0 && bytes[actualLength - 1] == 0) {
            actualLength--;
        }
    }

    NSString* string = [[NSString alloc] initWithBytes:bytes length:actualLength encoding:encoding];
    if (!string && formatId == CF_TEXT) {
        string = [[NSString alloc] initWithBytes:bytes length:actualLength encoding:NSISOLatin1StringEncoding];
    }

    return string;
}

static UINT cliprdr_send_client_capabilities(CliprdrClientContext* cliprdr) {
    if (!cliprdr || !cliprdr->ClientCapabilities) {
        return CHANNEL_RC_OK;
    }

    CLIPRDR_GENERAL_CAPABILITY_SET generalCapabilitySet = {0};
    generalCapabilitySet.capabilitySetType = CB_CAPSTYPE_GENERAL;
    generalCapabilitySet.capabilitySetLength = CB_CAPSTYPE_GENERAL_LEN;
    generalCapabilitySet.version = CB_CAPS_VERSION_2;
    generalCapabilitySet.generalFlags = CB_USE_LONG_FORMAT_NAMES;

    CLIPRDR_CAPABILITIES capabilities = {0};
    capabilities.common.msgType = CB_CLIP_CAPS;
    capabilities.cCapabilitiesSets = 1;
    capabilities.capabilitySets = (CLIPRDR_CAPABILITY_SET*)&generalCapabilitySet;

    return cliprdr->ClientCapabilities(cliprdr, &capabilities);
}

static UINT cliprdr_send_client_format_list(CliprdrClientContext* cliprdr) {
    if (!cliprdr || !cliprdr->ClientFormatList) {
        return CHANNEL_RC_OK;
    }

    SwiftRDPContext* context = cliprdr->custom ? (SwiftRDPContext*)cliprdr->custom : NULL;
    NSString* string = cached_pasteboard_string(context);
    CLIPRDR_FORMAT formats[2] = {0};
    UINT32 numFormats = 0;

    if (string) {
        formats[numFormats++].formatId = CF_UNICODETEXT;
        formats[numFormats++].formatId = CF_TEXT;
    }

    CLIPRDR_FORMAT_LIST formatList = {0};
    formatList.common.msgType = CB_FORMAT_LIST;
    formatList.numFormats = numFormats;
    formatList.formats = formats;

    if (context) {
        context->lastPasteboardChangeCount = cached_pasteboard_change_count(context);
    }

    return cliprdr->ClientFormatList(cliprdr, &formatList);
}

static UINT cliprdr_send_client_format_list_response(CliprdrClientContext* cliprdr, BOOL ok) {
    if (!cliprdr || !cliprdr->ClientFormatListResponse) {
        return CHANNEL_RC_OK;
    }

    CLIPRDR_FORMAT_LIST_RESPONSE response = {0};
    response.common.msgType = CB_FORMAT_LIST_RESPONSE;
    response.common.msgFlags = ok ? CB_RESPONSE_OK : CB_RESPONSE_FAIL;
    return cliprdr->ClientFormatListResponse(cliprdr, &response);
}

static UINT cliprdr_request_server_format(CliprdrClientContext* cliprdr, UINT32 formatId) {
    if (!cliprdr || !cliprdr->ClientFormatDataRequest || formatId == 0) {
        return CHANNEL_RC_OK;
    }

    CLIPRDR_FORMAT_DATA_REQUEST request = {0};
    request.common.msgType = CB_FORMAT_DATA_REQUEST;
    request.requestedFormatId = formatId;

    if (cliprdr->custom) {
        ((SwiftRDPContext*)cliprdr->custom)->requestedClipboardFormat = formatId;
    }

    return cliprdr->ClientFormatDataRequest(cliprdr, &request);
}

static UINT my_cliprdr_monitor_ready(CliprdrClientContext* cliprdr, const CLIPRDR_MONITOR_READY* monitorReady) {
    (void)monitorReady;
    UINT rc = cliprdr_send_client_capabilities(cliprdr);
    if (rc != CHANNEL_RC_OK) {
        return rc;
    }
    return cliprdr_send_client_format_list(cliprdr);
}

static UINT my_cliprdr_server_capabilities(CliprdrClientContext* cliprdr, const CLIPRDR_CAPABILITIES* capabilities) {
    (void)cliprdr;
    (void)capabilities;
    return CHANNEL_RC_OK;
}

static UINT my_cliprdr_server_format_list(CliprdrClientContext* cliprdr, const CLIPRDR_FORMAT_LIST* formatList) {
    if (!formatList) {
        return CHANNEL_RC_OK;
    }

    UINT32 requestedFormat = 0;
    for (UINT32 index = 0; index < formatList->numFormats; index++) {
        const UINT32 formatId = formatList->formats[index].formatId;
        if (formatId == CF_UNICODETEXT) {
            requestedFormat = CF_UNICODETEXT;
            break;
        }
        if (formatId == CF_TEXT && requestedFormat == 0) {
            requestedFormat = CF_TEXT;
        }
    }

    UINT rc = cliprdr_send_client_format_list_response(cliprdr, TRUE);
    if (rc != CHANNEL_RC_OK) {
        return rc;
    }

    return cliprdr_request_server_format(cliprdr, requestedFormat);
}

static UINT my_cliprdr_server_format_list_response(CliprdrClientContext* cliprdr,
                                                   const CLIPRDR_FORMAT_LIST_RESPONSE* formatListResponse) {
    (void)cliprdr;
    (void)formatListResponse;
    return CHANNEL_RC_OK;
}

static UINT my_cliprdr_server_format_data_request(CliprdrClientContext* cliprdr,
                                                  const CLIPRDR_FORMAT_DATA_REQUEST* formatDataRequest) {
    if (!cliprdr || !cliprdr->ClientFormatDataResponse || !formatDataRequest) {
        return CHANNEL_RC_OK;
    }

    SwiftRDPContext* context = cliprdr->custom ? (SwiftRDPContext*)cliprdr->custom : NULL;
    NSString* string = cached_pasteboard_string(context);
    NSData* data = clipboard_data_for_format(string, formatDataRequest->requestedFormatId);

    CLIPRDR_FORMAT_DATA_RESPONSE response = {0};
    response.common.msgType = CB_FORMAT_DATA_RESPONSE;
    response.common.msgFlags = data ? CB_RESPONSE_OK : CB_RESPONSE_FAIL;
    response.common.dataLen = data ? (UINT32)[data length] : 0;
    response.requestedFormatData = data ? (const BYTE*)[data bytes] : NULL;

    return cliprdr->ClientFormatDataResponse(cliprdr, &response);
}

static UINT my_cliprdr_server_format_data_response(CliprdrClientContext* cliprdr,
                                                   const CLIPRDR_FORMAT_DATA_RESPONSE* formatDataResponse) {
    if (!cliprdr || !formatDataResponse || (formatDataResponse->common.msgFlags & CB_RESPONSE_FAIL)) {
        return CHANNEL_RC_OK;
    }

    UINT32 formatId = 0;
    if (cliprdr->custom) {
        formatId = ((SwiftRDPContext*)cliprdr->custom)->requestedClipboardFormat;
    }

    NSString* string = string_from_clipboard_data(formatDataResponse->requestedFormatData,
                                                 formatDataResponse->common.dataLen,
                                                 formatId);
    set_pasteboard_string(cliprdr, string);
    return CHANNEL_RC_OK;
}

static void cliprdr_poll_local_pasteboard(SwiftRDPContext* context) {
    if (!context || !context->cliprdr) {
        return;
    }

    const NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - context->lastClipboardPollTime < 0.25) {
        return;
    }
    context->lastClipboardPollTime = now;

    const NSInteger changeCount = cached_pasteboard_change_count(context);
    if (context->lastPasteboardChangeCount == changeCount) {
        BOOL shouldPoll = FALSE;
        @synchronized([SwiftRDPBridge class]) {
            shouldPoll = !context->pasteboardPollPending;
            context->pasteboardPollPending = TRUE;
        }

        if (shouldPoll) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSPasteboard* pasteboard = [NSPasteboard generalPasteboard];
                NSString* string = [[pasteboard stringForType:NSPasteboardTypeString] copy];
                update_cached_pasteboard(context, string, [pasteboard changeCount]);
            });
        }
        return;
    }

    cliprdr_send_client_format_list(context->cliprdr);
}

static BOOL my_EndPaint(rdpContext* context) {
    if (!context) {
        return FALSE;
    }

    SwiftRDPContext* swiftContext = (SwiftRDPContext*)context;
    BOOL result = TRUE;

    if (swiftContext->originalEndPaint) {
        result = swiftContext->originalEndPaint(context);
    }

    if (!result || !context || !context->gdi || !context->gdi->primary_buffer) {
        return result;
    }

    rdpGdi* gdi = context->gdi;
    if (gdi->width <= 0 || gdi->height <= 0 || gdi->stride == 0) {
        return result;
    }

    const size_t byteCount = (size_t)gdi->stride * (size_t)gdi->height;
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL,
                                                              gdi->primary_buffer,
                                                              byteCount,
                                                              NULL);
    if (!provider) {
        return result;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst;
    CGImageRef image = CGImageCreate((size_t)gdi->width,
                                     (size_t)gdi->height,
                                     8,
                                     32,
                                     (size_t)gdi->stride,
                                     colorSpace,
                                     bitmapInfo,
                                     provider,
                                     NULL,
                                     false,
                                     kCGRenderingIntentDefault);

    SwiftRDPBridge* bridge = bridge_from_context(context);
    if (image && bridge.delegate) {
        [bridge.delegate rdpBridge:bridge didUpdateImage:image width:gdi->width height:gdi->height];
    }

    if (image) CGImageRelease(image);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);

    return result;
}

static BOOL my_DesktopResize(rdpContext* context) {
    if (!context || !context->gdi || !context->settings) {
        return FALSE;
    }

    const UINT32 width = freerdp_settings_get_uint32(context->settings, FreeRDP_DesktopWidth);
    const UINT32 height = freerdp_settings_get_uint32(context->settings, FreeRDP_DesktopHeight);
    printf("DesktopResize: %" PRIu32 "x%" PRIu32 "\n", width, height);
    return gdi_resize(context->gdi, width, height);
}

static void my_OnChannelConnected(void* context, const ChannelConnectedEventArgs* e) {
    if (!context || !e || !e->name) {
        return;
    }

    printf("Channel connected: %s\n", e->name);
    rdpContext* rdp = (rdpContext*)context;
    SwiftRDPContext* swiftContext = (SwiftRDPContext*)context;
    if (strcmp(e->name, CLIPRDR_CHANNEL_NAME) == 0) {
        CliprdrClientContext* cliprdr = (CliprdrClientContext*)e->pInterface;
        swiftContext->cliprdr = cliprdr;
        swiftContext->requestedClipboardFormat = 0;
        swiftContext->lastPasteboardChangeCount = -1;
        swiftContext->lastClipboardPollTime = 0;

        if (cliprdr) {
            cliprdr->custom = swiftContext;
            cliprdr->MonitorReady = my_cliprdr_monitor_ready;
            cliprdr->ServerCapabilities = my_cliprdr_server_capabilities;
            cliprdr->ServerFormatList = my_cliprdr_server_format_list;
            cliprdr->ServerFormatListResponse = my_cliprdr_server_format_list_response;
            cliprdr->ServerFormatDataRequest = my_cliprdr_server_format_data_request;
            cliprdr->ServerFormatDataResponse = my_cliprdr_server_format_data_response;
        }
        return;
    }

    if (strcmp(e->name, RDPGFX_DVC_CHANNEL_NAME) == 0) {
        if (rdp->gdi) {
            gdi_graphics_pipeline_init(rdp->gdi, (RdpgfxClientContext*)e->pInterface);
        }
        return;
    }

    freerdp_client_OnChannelConnectedEventHandler(context, e);
}

static void my_OnChannelDisconnected(void* context, const ChannelDisconnectedEventArgs* e) {
    if (!context || !e || !e->name) {
        return;
    }

    printf("Channel disconnected: %s\n", e->name);
    rdpContext* rdp = (rdpContext*)context;
    SwiftRDPContext* swiftContext = (SwiftRDPContext*)context;
    if (strcmp(e->name, CLIPRDR_CHANNEL_NAME) == 0) {
        swiftContext->cliprdr = NULL;
        swiftContext->requestedClipboardFormat = 0;
        return;
    }

    if (strcmp(e->name, RDPGFX_DVC_CHANNEL_NAME) == 0) {
        if (rdp->gdi) {
            gdi_graphics_pipeline_uninit(rdp->gdi, (RdpgfxClientContext*)e->pInterface);
        }
        return;
    }

    freerdp_client_OnChannelDisconnectedEventHandler(context, e);
}

static BOOL my_PreConnect(freerdp* instance) {
    rdpSettings* settings = instance->context->settings;
    SwiftRDPContext* swiftContext = (SwiftRDPContext*)instance->context;
    
    freerdp_settings_set_uint32(settings, FreeRDP_DesktopWidth, swiftContext->requestedWidth);
    freerdp_settings_set_uint32(settings, FreeRDP_DesktopHeight, swiftContext->requestedHeight);
    freerdp_settings_set_uint32(settings, FreeRDP_ColorDepth, swiftContext->requestedColorDepth);
    
    // Security layers
    freerdp_settings_set_bool(settings, FreeRDP_NlaSecurity, TRUE);
    freerdp_settings_set_bool(settings, FreeRDP_TlsSecurity, TRUE);
    freerdp_settings_set_bool(settings, FreeRDP_RdpSecurity, TRUE);
    
    // Let FreeRDP negotiate modern graphics capabilities. Some servers
    // deactivate the session during activation if these are suppressed.
    freerdp_settings_set_bool(settings, FreeRDP_RemoteFxCodec, swiftContext->enableRemoteFx);
    freerdp_settings_set_bool(settings, FreeRDP_NSCodec, TRUE);
    freerdp_settings_set_bool(settings, FreeRDP_SupportGraphicsPipeline, TRUE);
    freerdp_settings_set_bool(settings, FreeRDP_GfxH264, TRUE);
    freerdp_settings_set_bool(settings, FreeRDP_GfxAVC444, FALSE);
    freerdp_settings_set_bool(settings, FreeRDP_GfxAVC444v2, FALSE);
    freerdp_settings_set_uint32(settings, FreeRDP_FrameAcknowledge, 0);
    freerdp_settings_set_bool(settings, FreeRDP_GfxSuspendFrameAck, TRUE);
    freerdp_settings_set_bool(settings, FreeRDP_SoftwareGdi, TRUE);

    printf("Graphics settings: GFX=%d AVC420=%d AVC444=%d RFX=%d ACK=%u GFX_ACK=%d\n",
           freerdp_settings_get_bool(settings, FreeRDP_SupportGraphicsPipeline),
           freerdp_settings_get_bool(settings, FreeRDP_GfxH264),
           freerdp_settings_get_bool(settings, FreeRDP_GfxAVC444),
           freerdp_settings_get_bool(settings, FreeRDP_RemoteFxCodec),
           freerdp_settings_get_uint32(settings, FreeRDP_FrameAcknowledge),
           !freerdp_settings_get_bool(settings, FreeRDP_GfxSuspendFrameAck));

    freerdp_settings_set_bool(settings,
                              FreeRDP_DeviceRedirection,
                              swiftContext->hasSharedFolder || swiftContext->enableAudioPlayback);
    freerdp_settings_set_bool(settings, FreeRDP_RedirectDrives, FALSE);
    freerdp_settings_set_bool(settings, FreeRDP_RedirectSmartCards, FALSE);
    freerdp_settings_set_bool(settings, FreeRDP_RedirectPrinters, FALSE);
    freerdp_settings_set_bool(settings, FreeRDP_RedirectSerialPorts, FALSE);
    freerdp_settings_set_bool(settings, FreeRDP_RedirectParallelPorts, FALSE);
    freerdp_settings_set_bool(settings, FreeRDP_RedirectClipboard, TRUE);
    freerdp_settings_set_uint32(settings,
                                FreeRDP_ClipboardFeatureMask,
                                CLIPRDR_FLAG_LOCAL_TO_REMOTE | CLIPRDR_FLAG_REMOTE_TO_LOCAL);
    freerdp_settings_set_bool(settings, FreeRDP_AudioPlayback, swiftContext->enableAudioPlayback);
    freerdp_settings_set_bool(settings, FreeRDP_AudioCapture, FALSE);

    if (PubSub_SubscribeChannelConnected(instance->context->pubSub, my_OnChannelConnected) < 0) {
        printf("PubSub_SubscribeChannelConnected failed\n");
        return FALSE;
    }

    if (PubSub_SubscribeChannelDisconnected(instance->context->pubSub, my_OnChannelDisconnected) < 0) {
        printf("PubSub_SubscribeChannelDisconnected failed\n");
        return FALSE;
    }

    if (!freerdp_client_load_addins(instance->context->channels, settings)) {
        printf("freerdp_client_load_addins failed\n");
        return FALSE;
    }

    return TRUE;
}

static BOOL my_PostConnect(freerdp* instance) {
    printf("PostConnect called - Connection established!\n");

    if (!gdi_init(instance, PIXEL_FORMAT_BGRA32)) {
        printf("gdi_init failed\n");
        return FALSE;
    }

    SwiftRDPContext* swiftContext = (SwiftRDPContext*)instance->context;
    swiftContext->originalEndPaint = instance->context->update->EndPaint;
    instance->context->update->DesktopResize = my_DesktopResize;
    instance->context->update->EndPaint = my_EndPaint;

    return TRUE;
}

static void my_PostDisconnect(freerdp* instance) {
    printf("PostDisconnect called\n");
    gdi_free(instance);
}

static int my_LogonErrorInfo(freerdp* instance, UINT32 data, UINT32 type) {
    printf("LogonErrorInfo: data=0x%x, type=0x%x\n", data, type);
    return 1;
}

@implementation SwiftRDPBridge {
    freerdp *_instance;
    BOOL _connected;
}

- (instancetype)init {
    self = [super init];
    return self;
}

- (void)dealloc {
    [self freeInstance];
}

- (void)createInstance {
    RDP_CLIENT_ENTRY_POINTS entryPoints = { 0 };
    entryPoints.Size = sizeof(RDP_CLIENT_ENTRY_POINTS);
    entryPoints.Version = RDP_CLIENT_INTERFACE_VERSION;
    entryPoints.ContextSize = sizeof(SwiftRDPContext);

    rdpContext* context = freerdp_client_context_new(&entryPoints);
    if (!context || !context->instance) {
        return;
    }

    _instance = context->instance;
    _instance->AuthenticateEx = my_AuthenticateEx;
    _instance->PreConnect = my_PreConnect;
    _instance->PostConnect = my_PostConnect;
    _instance->PostDisconnect = my_PostDisconnect;
    _instance->LogonErrorInfo = my_LogonErrorInfo;

    SwiftRDPContext* swiftContext = (SwiftRDPContext*)_instance->context;
    swiftContext->bridge = (__bridge void*)self;
    swiftContext->requestedWidth = 1024;
    swiftContext->requestedHeight = 768;
    swiftContext->requestedColorDepth = 32;
    swiftContext->enableRemoteFx = TRUE;
    swiftContext->enableAudioPlayback = TRUE;
    swiftContext->hasSharedFolder = FALSE;
    swiftContext->lastPasteboardChangeCount = -1;
    swiftContext->cachedPasteboardChangeCount = -1;
}

- (void)freeInstance {
    if (_instance) {
        if (_connected) {
            freerdp_disconnect(_instance);
            _connected = NO;
        }
        SwiftRDPContext* swiftContext = (SwiftRDPContext*)_instance->context;
        if (swiftContext && swiftContext->cachedPasteboardString) {
            CFRelease(swiftContext->cachedPasteboardString);
            swiftContext->cachedPasteboardString = NULL;
        }
        freerdp_client_context_free(_instance->context);
        _instance = NULL;
    }
}

- (BOOL)connectToHost:(NSString *)host
                 port:(int)port
                 user:(NSString *)user
             password:(NSString *)password
                width:(int)width
           height:(int)height
       colorDepth:(int)colorDepth
   enableRemoteFx:(BOOL)enableRemoteFx
enableAudioPlayback:(BOOL)enableAudioPlayback
 sharedFolderName:(NSString *)sharedFolderName
 sharedFolderPath:(NSString *)sharedFolderPath {
    [self freeInstance];
    [self createInstance];
    if (!_instance || !_instance->context || !_instance->context->settings) return NO;
    
    rdpSettings *settings = _instance->context->settings;
    SwiftRDPContext* swiftContext = (SwiftRDPContext*)_instance->context;
    swiftContext->requestedWidth = MAX(640, width);
    swiftContext->requestedHeight = MAX(480, height);
    swiftContext->requestedColorDepth = colorDepth == 16 || colorDepth == 24 ? colorDepth : 32;
    swiftContext->enableRemoteFx = enableRemoteFx;
    swiftContext->enableAudioPlayback = enableAudioPlayback;
    swiftContext->hasSharedFolder = sharedFolderPath.length > 0;

    NSString* target = [NSString stringWithFormat:@"/v:%@:%d", host, port];
    NSString* username = [NSString stringWithFormat:@"/u:%@", user];
    NSString* size = [NSString stringWithFormat:@"/size:%dx%d", swiftContext->requestedWidth, swiftContext->requestedHeight];
    NSString* bpp = [NSString stringWithFormat:@"/bpp:%d", swiftContext->requestedColorDepth];
    NSString* sound = enableAudioPlayback ? @"/sound:sys:mac" : @"/audio-mode:none";
    char* argv[] = {
        (char*)"SwiftRDP",
        (char*)[target UTF8String],
        (char*)[username UTF8String],
        (char*)[size UTF8String],
        (char*)[bpp UTF8String],
        (char*)[sound UTF8String],
        (char*)"/network:lan"
    };

    const int argc = (int)(sizeof(argv) / sizeof(argv[0]));
    if (freerdp_client_settings_parse_command_line(settings, argc, argv, FALSE) < 0) {
        printf("freerdp_client_settings_parse_command_line failed\n");
        return NO;
    }

    if (sharedFolderPath.length > 0) {
        NSString* driveName = sharedFolderName.length > 0 ? sharedFolderName : @"Mac";
        const char* params[] = {
            "drive",
            [driveName UTF8String],
            [sharedFolderPath UTF8String]
        };

        if (!freerdp_client_add_device_channel(settings, 3, params)) {
            printf("freerdp_client_add_device_channel failed for %s\n", [sharedFolderPath UTF8String]);
            return NO;
        }
    }

    printf("Parsed target host=%s port=%" PRIu32 "\n",
           freerdp_settings_get_string(settings, FreeRDP_ServerHostname),
           freerdp_settings_get_uint32(settings, FreeRDP_ServerPort));

    freerdp_settings_set_string(settings, FreeRDP_Password, [password UTF8String]);

    // TODO: expose certificate handling in the UI and support fingerprint pinning.
    freerdp_settings_set_bool(settings, FreeRDP_IgnoreCertificate, TRUE);
    freerdp_settings_set_bool(settings, FreeRDP_Authentication, TRUE);
    
    _connected = freerdp_connect(_instance);
    return _connected;
}

- (void)disconnect {
    if (_instance && _connected) {
        freerdp_disconnect(_instance);
        _connected = NO;
    }
}

- (BOOL)process {
    if (!_instance) return FALSE;
    BOOL result = freerdp_check_event_handles(_instance->context);
    if (!result) {
        _connected = NO;
    } else if (_connected) {
        cliprdr_poll_local_pasteboard((SwiftRDPContext*)_instance->context);
    }
    return result;
}

- (BOOL)sendMouseEventWithFlags:(uint16_t)flags x:(uint16_t)x y:(uint16_t)y {
    if (!_instance || !_connected || !_instance->context || !_instance->context->input) {
        return NO;
    }

    return freerdp_input_send_mouse_event(_instance->context->input, flags, x, y);
}

- (BOOL)sendUnicodeKeyboardEvent:(uint16_t)code down:(BOOL)down {
    if (!_instance || !_connected || !_instance->context || !_instance->context->input) {
        return NO;
    }

    const UINT16 flags = down ? 0 : KBD_FLAGS_RELEASE;
    return freerdp_input_send_unicode_keyboard_event(_instance->context->input, flags, code);
}

- (BOOL)sendKeyboardScancode:(uint32_t)scancode down:(BOOL)down {
    if (!_instance || !_connected || !_instance->context || !_instance->context->input) {
        return NO;
    }

    const UINT32 rdpScancode = MAKE_RDP_SCANCODE(RDP_SCANCODE_CODE(scancode), RDP_SCANCODE_EXTENDED(scancode));
    return freerdp_input_send_keyboard_event_ex(_instance->context->input, down, FALSE, rdpScancode);
}

- (BOOL)sendAppleKeycode:(uint32_t)keycode down:(BOOL)down {
    if (!_instance || !_connected || !_instance->context || !_instance->context->input) {
        return NO;
    }

    const DWORD vkcode = GetVirtualKeyCodeFromKeycode(keycode, WINPR_KEYCODE_TYPE_APPLE);
    if (vkcode == 0) {
        return NO;
    }

    const DWORD scancode = GetVirtualScanCodeFromVirtualKeyCode(vkcode, WINPR_KBD_TYPE_IBM_ENHANCED);
    if (scancode == 0) {
        return NO;
    }

    return freerdp_input_send_keyboard_event_ex(_instance->context->input, down, FALSE, scancode);
}

- (NSString *)lastErrorDescription {
    if (!_instance || !_instance->context) {
        return @"No FreeRDP context";
    }

    UINT32 code = freerdp_get_last_error(_instance->context);
    if (code == FREERDP_ERROR_SUCCESS) {
        return @"Disconnected";
    }

    const char* name = freerdp_get_last_error_name(code);
    const char* message = freerdp_get_last_error_string(code);
    if (name && message) {
        return [NSString stringWithFormat:@"%s: %s", name, message];
    }
    if (name) {
        return [NSString stringWithUTF8String:name];
    }
    return [NSString stringWithFormat:@"FreeRDP error 0x%08x", code];
}

@end
