#import "LegacyXLSReaderBridge.h"

#import "../Vendor/libxls/include/xls.h"
#import "../Vendor/libxls/include/libxls/xlsstruct.h"

NSErrorDomain const LegacyXLSReaderBridgeErrorDomain = @"LegacyXLSReaderBridgeErrorDomain";

@implementation LegacyXLSReaderBridge

+ (nullable NSArray<NSArray<NSString *> *> *)parseXLSData:(NSData *)data
                                                   error:(NSError * _Nullable * _Nullable)error {
    xls_error_t openError = LIBXLS_OK;
    xlsWorkBook *workbook = xls_open_buffer((const unsigned char *)data.bytes, data.length, "UTF-8", &openError);
    if (workbook == NULL) {
        if (error != NULL) {
            NSString *reason = [NSString stringWithUTF8String:xls_getError(openError) ?: "Unable to open XLS"];
            LegacyXLSReaderBridgeErrorCode code = openError == LIBXLS_ERROR_UNSUPPORTED_ENCRYPTION
                ? LegacyXLSReaderBridgeErrorCodePasswordProtected
                : LegacyXLSReaderBridgeErrorCodeOpenFailed;
            *error = [NSError errorWithDomain:LegacyXLSReaderBridgeErrorDomain
                                         code:code
                                     userInfo:@{NSLocalizedDescriptionKey: reason}];
        }
        return nil;
    }

    NSMutableArray<NSArray<NSString *> *> *bestSheetRows = nil;
    NSUInteger bestScore = 0;

    for (DWORD sheetIndex = 0; sheetIndex < workbook->sheets.count; sheetIndex++) {
        xlsWorkSheet *worksheet = xls_getWorkSheet(workbook, (int)sheetIndex);
        if (worksheet == NULL) {
            continue;
        }

        xls_error_t parseError = xls_parseWorkSheet(worksheet);
        if (parseError != LIBXLS_OK) {
            xls_close_WS(worksheet);
            continue;
        }

        NSMutableArray<NSArray<NSString *> *> *sheetRows = [NSMutableArray array];
        NSUInteger populatedCellCount = 0;

        for (WORD rowIndex = 0; rowIndex <= worksheet->rows.lastrow; rowIndex++) {
            NSMutableArray<NSString *> *row = [NSMutableArray array];
            BOOL hasVisibleCells = NO;

            for (WORD columnIndex = 0; columnIndex <= worksheet->rows.lastcol; columnIndex++) {
                xlsCell *cell = xls_cell(worksheet, rowIndex, columnIndex);
                NSString *value = [self stringValueForCell:cell];
                if (value.length > 0) {
                    hasVisibleCells = YES;
                    populatedCellCount += 1;
                }
                [row addObject:value];
            }

            while (row.count > 0 && ((NSString *)row.lastObject).length == 0) {
                [row removeLastObject];
            }

            if (hasVisibleCells && row.count > 0) {
                [sheetRows addObject:[row copy]];
            }
        }

        if (populatedCellCount > bestScore) {
            bestScore = populatedCellCount;
            bestSheetRows = sheetRows;
        }

        xls_close_WS(worksheet);
    }

    xls_close_WB(workbook);

    if (bestSheetRows.count == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:LegacyXLSReaderBridgeErrorDomain
                                         code:LegacyXLSReaderBridgeErrorCodeNoRowsFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"No rows found"}];
        }
        return nil;
    }

    return [bestSheetRows copy];
}

+ (NSString *)stringValueForCell:(xlsCell *)cell {
    if (cell == NULL || cell->isHidden) {
        return @"";
    }

    switch (cell->id) {
        case XLS_RECORD_RK:
        case XLS_RECORD_MULRK:
        case XLS_RECORD_NUMBER:
            return [NSString stringWithFormat:@"%.15g", cell->d];
        case XLS_RECORD_FORMULA:
        case XLS_RECORD_FORMULA_ALT:
            if (cell->l == 0) {
                return [NSString stringWithFormat:@"%.15g", cell->d];
            }
            if (cell->str != NULL) {
                if (strcmp(cell->str, "bool") == 0) {
                    return ((int)cell->d != 0) ? @"true" : @"false";
                }
                if (strcmp(cell->str, "error") == 0) {
                    return @"";
                }
                return [NSString stringWithUTF8String:cell->str] ?: @"";
            }
            return @"";
        default:
            if (cell->str != NULL) {
                return [NSString stringWithUTF8String:cell->str] ?: @"";
            }
            return @"";
    }
}

@end
