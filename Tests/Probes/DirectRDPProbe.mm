#import <Foundation/Foundation.h>

#include <freerdp/freerdp.h>
#include <freerdp/client.h>
#include <freerdp/client/cmdline.h>
#include <freerdp/settings.h>
#include <inttypes.h>

static BOOL probeAuthenticate(freerdp* instance, char** username, char** password, char** domain, rdp_auth_reason reason) {
    printf("AuthenticateEx called (reason: %d)\n", reason);
    return password && *password && strlen(*password) > 0;
}

static BOOL probePostConnect(freerdp* instance) {
    printf("PostConnect called\n");
    return TRUE;
}

static void probePostDisconnect(freerdp* instance) {
    printf("PostDisconnect called\n");
}

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        if (argc < 4) {
            printf("usage: DirectRDPProbe <host> <user> <password> [port]\n");
            return 1;
        }

        NSString* host = [NSString stringWithUTF8String:argv[1]];
        NSString* user = [NSString stringWithUTF8String:argv[2]];
        NSString* password = [NSString stringWithUTF8String:argv[3]];
        int port = argc > 4 ? atoi(argv[4]) : 3389;

        RDP_CLIENT_ENTRY_POINTS entryPoints = { 0 };
        entryPoints.Size = sizeof(RDP_CLIENT_ENTRY_POINTS);
        entryPoints.Version = RDP_CLIENT_INTERFACE_VERSION;
        entryPoints.ContextSize = sizeof(rdpClientContext);

        rdpContext* context = freerdp_client_context_new(&entryPoints);
        if (!context || !context->instance || !context->settings) {
            printf("CONTEXT_FAILED\n");
            return 10;
        }

        freerdp* instance = context->instance;
        instance->AuthenticateEx = probeAuthenticate;
        instance->PostConnect = probePostConnect;
        instance->PostDisconnect = probePostDisconnect;

        NSString* target = [NSString stringWithFormat:@"/v:%@:%d", host, port];
        NSString* username = [NSString stringWithFormat:@"/u:%@", user];
        char* fargv[] = {
            (char*)"DirectRDPProbe",
            (char*)[target UTF8String],
            (char*)[username UTF8String],
            (char*)"/cert:ignore",
            (char*)"/size:1024x768",
            (char*)"/bpp:32",
            (char*)"/network:lan"
        };
        int fargc = (int)(sizeof(fargv) / sizeof(fargv[0]));
        if (freerdp_client_settings_parse_command_line(context->settings, fargc, fargv, FALSE) < 0) {
            printf("PARSE_FAILED\n");
            freerdp_client_context_free(context);
            return 11;
        }

        freerdp_settings_set_string(context->settings, FreeRDP_Password, [password UTF8String]);
        printf("Parsed target host=%s port=%" PRIu32 "\n",
               freerdp_settings_get_string(context->settings, FreeRDP_ServerHostname),
               freerdp_settings_get_uint32(context->settings, FreeRDP_ServerPort));

        BOOL connected = freerdp_connect(instance);
        if (!connected) {
            UINT32 code = freerdp_get_last_error(context);
            printf("CONNECT_FAILED: %s: %s\n",
                   freerdp_get_last_error_name(code),
                   freerdp_get_last_error_string(code));
            freerdp_client_context_free(context);
            return 12;
        }

        printf("CONNECT_OK\n");
        NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:10.0];
        while ([deadline timeIntervalSinceNow] > 0) {
            if (!freerdp_check_event_handles(context)) {
                UINT32 code = freerdp_get_last_error(context);
                printf("PROCESS_STOPPED: %s: %s\n",
                       freerdp_get_last_error_name(code),
                       freerdp_get_last_error_string(code));
                freerdp_disconnect(instance);
                freerdp_client_context_free(context);
                return 13;
            }
            [NSThread sleepForTimeInterval:0.01];
        }

        printf("PROCESS_OK_10S\n");
        freerdp_disconnect(instance);
        freerdp_client_context_free(context);
        return 0;
    }
}
