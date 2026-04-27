#import <Foundation/Foundation.h>

#import "../Vendor/libxls/include/libxls/ole.h"

static NSString * const ProtectedXLSXStreamErrorDomain = @"ProtectedXLSXStreamErrorDomain";

static NSData *ReadOLEStream(OLE2 *ole, const char *name, int *errorCode) {
    OLE2Stream *stream = ole2_fopen(ole, name);
    if (stream == NULL) {
        if (errorCode != NULL) { *errorCode = 2; }
        return nil;
    }

    NSMutableData *data = [NSMutableData dataWithLength:stream->size];
    size_t read = ole2_read(data.mutableBytes, 1, stream->size, stream);
    ole2_fclose(stream);

    if (read != stream->size) {
        if (errorCode != NULL) { *errorCode = 3; }
        return nil;
    }

    return data;
}

const char *ProtectedXLSXCopyStreamsJSON(const unsigned char *bytes, int length, int *errorCode) {
    if (errorCode != NULL) { *errorCode = 0; }
    if (bytes == NULL || length <= 0) {
        if (errorCode != NULL) { *errorCode = 1; }
        return NULL;
    }

    OLE2 *ole = ole2_open_buffer(bytes, (size_t)length);
    if (ole == NULL) {
        if (errorCode != NULL) { *errorCode = 1; }
        return NULL;
    }

    NSData *encryptionInfo = ReadOLEStream(ole, "EncryptionInfo", errorCode);
    NSData *encryptedPackage = ReadOLEStream(ole, "EncryptedPackage", errorCode);
    ole2_close(ole);

    if (encryptionInfo == nil || encryptedPackage == nil) {
        return NULL;
    }

    NSDictionary *payload = @{
        @"encryptionInfo": [encryptionInfo base64EncodedStringWithOptions:0],
        @"encryptedPackage": [encryptedPackage base64EncodedStringWithOptions:0]
    };

    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (json == nil) {
        if (errorCode != NULL) { *errorCode = 4; }
        return NULL;
    }

    char *result = malloc(json.length + 1);
    if (result == NULL) {
        if (errorCode != NULL) { *errorCode = 5; }
        return NULL;
    }

    memcpy(result, json.bytes, json.length);
    result[json.length] = '\0';
    return result;
}

void ProtectedXLSXFreeCString(char *pointer) {
    if (pointer != NULL) {
        free(pointer);
    }
}
