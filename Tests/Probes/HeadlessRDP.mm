#import <Foundation/Foundation.h>
#import "SwiftRDP/SwiftRDPBridge/SwiftRDPBridge.h"

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        if (argc < 4) {
            printf("usage: HeadlessRDP <host> <user> <password> [port]\n");
            return 1;
        }

        NSString* host = [NSString stringWithUTF8String:argv[1]];
        NSString* user = [NSString stringWithUTF8String:argv[2]];
        NSString* password = [NSString stringWithUTF8String:argv[3]];
        int port = argc > 4 ? atoi(argv[4]) : 3389;

        SwiftRDPBridge* bridge = [SwiftRDPBridge new];
        printf("Headless connect to %s:%d as %s\n", [host UTF8String], port, [user UTF8String]);

        BOOL connected = [bridge connectToHost:host
                                          port:port
                                          user:user
                                      password:password
                                         width:1024
                                        height:768
                                    colorDepth:32
                                enableRemoteFx:YES
                           enableAudioPlayback:NO
                              sharedFolderName:@""
                              sharedFolderPath:@""];
        if (!connected) {
            NSString* error = [bridge lastErrorDescription] ?: @"Unknown FreeRDP error";
            printf("CONNECT_FAILED: %s\n", [error UTF8String]);
            return 2;
        }

        printf("CONNECT_OK\n");

        NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:10.0];
        while ([deadline timeIntervalSinceNow] > 0) {
            if (![bridge process]) {
                NSString* error = [bridge lastErrorDescription] ?: @"Disconnected";
                printf("PROCESS_STOPPED: %s\n", [error UTF8String]);
                [bridge disconnect];
                return 3;
            }
            [NSThread sleepForTimeInterval:0.01];
        }

        printf("PROCESS_OK_10S\n");
        [bridge disconnect];
        return 0;
    }
}
