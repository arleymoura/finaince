#import <Foundation/Foundation.h>

#import "LegacyXLSReaderBridge.h"

const int32_t LegacyXLSErrorCodeOpenFailed = 1;
const int32_t LegacyXLSErrorCodeParseFailed = 2;
const int32_t LegacyXLSErrorCodeNoRowsFound = 3;

char *LegacyXLSCopyRowsJSON(const unsigned char *bytes, NSInteger length, int32_t *errorCode) {
    @autoreleasepool {
        NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)length];
        NSError *error = nil;
        NSArray<NSArray<NSString *> *> *rows = [LegacyXLSReaderBridge parseXLSData:data error:&error];
        if (rows == nil) {
            if (errorCode != NULL) {
                switch (error.code) {
                    case LegacyXLSReaderBridgeErrorCodeOpenFailed:
                        *errorCode = LegacyXLSErrorCodeOpenFailed;
                        break;
                    case LegacyXLSReaderBridgeErrorCodeNoRowsFound:
                        *errorCode = LegacyXLSErrorCodeNoRowsFound;
                        break;
                    default:
                        *errorCode = LegacyXLSErrorCodeParseFailed;
                        break;
                }
            }
            return NULL;
        }

        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:rows options:0 error:&error];
        if (jsonData == nil) {
            if (errorCode != NULL) {
                *errorCode = LegacyXLSErrorCodeParseFailed;
            }
            return NULL;
        }

        char *buffer = malloc(jsonData.length + 1);
        if (buffer == NULL) {
            if (errorCode != NULL) {
                *errorCode = LegacyXLSErrorCodeParseFailed;
            }
            return NULL;
        }

        memcpy(buffer, jsonData.bytes, jsonData.length);
        buffer[jsonData.length] = '\0';

        if (errorCode != NULL) {
            *errorCode = 0;
        }
        return buffer;
    }
}

void LegacyXLSFreeCString(char *pointer) {
    if (pointer != NULL) {
        free(pointer);
    }
}
