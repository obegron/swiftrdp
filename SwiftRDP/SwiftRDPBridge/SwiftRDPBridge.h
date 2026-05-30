#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@class SwiftRDPBridge;

@protocol SwiftRDPBridgeDelegate <NSObject>
- (void)rdpBridge:(SwiftRDPBridge *)bridge didUpdateImage:(CGImageRef)image width:(NSInteger)width height:(NSInteger)height;
@end

@interface SwiftRDPBridge : NSObject

@property (nonatomic, weak) id<SwiftRDPBridgeDelegate> delegate;

- (BOOL)connectToHost:(NSString *)host
                 port:(int)port
                 user:(NSString *)user
             password:(NSString *)password
                width:(int)width
           height:(int)height
       colorDepth:(int)colorDepth
   enableRemoteFx:(BOOL)enableRemoteFx
  sharedFolderName:(NSString *)sharedFolderName
  sharedFolderPath:(NSString *)sharedFolderPath;
- (void)disconnect;
- (BOOL)process;
- (BOOL)sendMouseEventWithFlags:(uint16_t)flags x:(uint16_t)x y:(uint16_t)y;
- (BOOL)sendUnicodeKeyboardEvent:(uint16_t)code down:(BOOL)down;
- (BOOL)sendKeyboardScancode:(uint32_t)scancode down:(BOOL)down;
- (BOOL)sendAppleKeycode:(uint32_t)keycode down:(BOOL)down;
- (NSString *)lastErrorDescription;

@end
