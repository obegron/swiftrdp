#import <Foundation/Foundation.h>
#import "SwiftRDP/SwiftRDPBridge/SwiftRDPBridge.h"

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        NSString* host = @"192.168.0.13";
        NSString* user = @"hej";
        NSString* password = @"hej";
        int port = 3389;

        if (argc > 1) host = [NSString stringWithUTF8String:argv[1]];
        if (argc > 2) user = [NSString stringWithUTF8String:argv[2]];
        if (argc > 3) password = [NSString stringWithUTF8String:argv[3]];
        if (argc > 4) port = atoi(argv[4]);

        SwiftRDPBridge* bridge = [SwiftRDPBridge new];
        printf("Headless connect to %s:%d as %s\n", [host UTF8String], port, [user UTF8String]);

        BOOL connected = [bridge connectToHost:host port:port user:user password:password];
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
