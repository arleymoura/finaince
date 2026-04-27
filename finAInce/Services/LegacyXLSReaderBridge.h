#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LegacyXLSReaderBridge : NSObject

+ (nullable NSArray<NSArray<NSString *> *> *)parseXLSData:(NSData *)data
                                                   error:(NSError * _Nullable * _Nullable)error;

@end

FOUNDATION_EXPORT NSErrorDomain const LegacyXLSReaderBridgeErrorDomain;

typedef NS_ERROR_ENUM(LegacyXLSReaderBridgeErrorDomain, LegacyXLSReaderBridgeErrorCode) {
    LegacyXLSReaderBridgeErrorCodeOpenFailed = 1,
    LegacyXLSReaderBridgeErrorCodeParseFailed = 2,
    LegacyXLSReaderBridgeErrorCodeNoRowsFound = 3,
    LegacyXLSReaderBridgeErrorCodePasswordProtected = 4,
};

NS_ASSUME_NONNULL_END
