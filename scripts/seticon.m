// 为文件设置自定义图标（不依赖 pyobjc）
// 对 .dmg 等系统类型文件，先临时改为普通文件类型再设置图标，最后恢复类型。
#import <Cocoa/Cocoa.h>

int main(int argc, const char *argv[]) {
    if (argc != 3) {
        fprintf(stderr, "Usage: seticon <source-file> <target-file>\n");
        return 1;
    }

    @autoreleasepool {
        NSString *source = [NSString stringWithUTF8String:argv[1]];
        NSString *target = [NSString stringWithUTF8String:argv[2]];
        NSFileManager *fm = [NSFileManager defaultManager];

        // 临时改为普通文本类型，绕过系统 UTI 对 .dmg 图标的限制
        [fm setAttributes:@{
            NSFileHFSTypeCode: @(NSHFSTypeCodeFromFileType(@"'TEXT'")),
            NSFileHFSCreatorCode: @(NSHFSTypeCodeFromFileType(@"'ttxt'"))
        } ofItemAtPath:target error:nil];

        NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:source];
        if (icon == nil) {
            fprintf(stderr, "Failed to read icon from %s\n", argv[1]);
            return 1;
        }

        BOOL ok = [[NSWorkspace sharedWorkspace] setIcon:icon forFile:target options:0];
        if (!ok) {
            fprintf(stderr, "Failed to set icon for %s\n", argv[2]);
            return 1;
        }

        // 恢复为 DMG 类型
        [fm setAttributes:@{
            NSFileHFSTypeCode: @(NSHFSTypeCodeFromFileType(@"'devi'")),
            NSFileHFSCreatorCode: @(NSHFSTypeCodeFromFileType(@"'ddsk'"))
        } ofItemAtPath:target error:nil];

        printf("Icon set successfully for %s\n", argv[2]);
        return 0;
    }
}
