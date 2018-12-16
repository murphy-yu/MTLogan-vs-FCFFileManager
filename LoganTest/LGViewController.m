/*
 * Copyright (c) 2018-present, 美团点评
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import "LGViewController.h"
#import "Logan.h"
#include <zlib.h>
#import <CommonCrypto/CommonCryptor.h>
#import "FCFileManager.h"

typedef enum : NSUInteger {
    LoganTypeAction = 1,  //用户行为日志
    LoganTypeNetwork = 2, //网络级日志
} LoganType;


@interface LGViewController ()
@property (nonatomic, assign) int count;
@property (weak, nonatomic) IBOutlet UITextView *filesInfo;
@property (weak, nonatomic) IBOutlet UITextField *ipText;
@property (strong, nonatomic) NSTimer *lllogTimer;
@end


@implementation LGViewController

- (void)dealloc
{
    [self.lllogTimer invalidate];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSData *keydata = [@"0123456789012345" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *ivdata = [@"0123456789012345" dataUsingEncoding:NSUTF8StringEncoding];
    uint64_t file_max = 10 * 1024 * 1024;
    // logan初始化，传入16位key，16位iv，写入文件最大大小(byte)
    loganInit(keydata, ivdata, file_max);
    
    loganClearAllLogs();
    
    // 将日志输出至控制台
    loganUseASL(NO);

    self.view.backgroundColor = [UIColor whiteColor];
    
    [self lllog:nil];
    
//    [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(allFilesInfo:) userInfo:nil repeats:YES];
    

}
- (IBAction)lllog:(id)sender {
    
    NSString *jsonFilePathString = [[NSBundle mainBundle] pathForResource:@"dummy" ofType:@"json"];
    NSData *jsonFileData = [NSData dataWithContentsOfFile:jsonFilePathString];
    NSLog(@"Single event size: %ld", jsonFileData.length);
    
    NSString *jsonFile = [[NSString alloc] initWithData:jsonFileData encoding:NSUTF8StringEncoding];
    
    NSError *error = nil;
    NSString *fcfFilePathString = @"foo";
    if ([FCFileManager isFileItemAtPath:fcfFilePathString error:&error]) {
        [FCFileManager removeItemAtPath:fcfFilePathString error:&error];
    }
    
    
    BOOL isLogan = YES;
    
    static const NSInteger maxCnt = 400;
    __block int curCnt = 0;
    self.lllogTimer = [NSTimer scheduledTimerWithTimeInterval:0.05f repeats:YES block:^(NSTimer * _Nonnull timer) {
        if (isLogan) {
            if (curCnt++ < maxCnt) {
                [self eventLogType:1 forLabel:[NSString stringWithFormat:@"%@ #$#[%d]", jsonFile, curCnt]];
            }
            else {
                [timer invalidate];
            }
        }
        else {
            NSError *err = nil;
            if (curCnt++ < maxCnt) {
                if (![FCFileManager isFileItemAtPath:fcfFilePathString error:&err]) {
                    [FCFileManager createFileAtPath:fcfFilePathString error:&err];
                }
                
                NSMutableString *str = [[FCFileManager readFileAtPath:fcfFilePathString error:&err] mutableCopy];
                [str appendString:[NSString stringWithFormat:@"%@ #$#[%d]", jsonFile, curCnt]];
                [FCFileManager writeFileAtPath:fcfFilePathString content:str];
                str = nil;
            }
            else {
                [timer invalidate];
                NSData *data = [FCFileManager readFileAtPathAsData:fcfFilePathString error:&err];
                NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                NSLog(@"Total file size: %ld, \n%@", data.length,str);
            }
        }
    }];
}

- (IBAction)allFilesInfo:(id)sender {
    NSDictionary *files = loganAllFilesInfo();

    NSMutableString *str = [[NSMutableString alloc] init];
    NSString *sizeString = nil;
    for (NSString *k in files.allKeys) {
        [str appendFormat:@"文件日期 %@，大小 %@byte\n", k, [files objectForKey:k]];
        sizeString = [files objectForKey:k];
    }

    self.filesInfo.text = str;
    NSLog(@"Total file size: %ld", [sizeString integerValue]);
}

- (IBAction)uploadFile:(id)sender {
    loganUploadFilePath(loganTodaysDate(), ^(NSString *_Nullable filePatch) {
        if (filePatch == nil) {
            return;
        }
        NSString *urlStr = [NSString stringWithFormat:@"http://%@:3000/logupload", self.ipText.text ?: @"127.0.0.1"];
        NSURL *url = [NSURL URLWithString:urlStr];
        NSMutableURLRequest *req = [[NSMutableURLRequest alloc] initWithURL:url cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:60];
        [req setHTTPMethod:@"POST"];
        [req addValue:@"binary/octet-stream" forHTTPHeaderField:@"Content-Type"];
        NSURL *fileUrl = [NSURL fileURLWithPath:filePatch];
        NSData *data = [NSData dataWithContentsOfURL:fileUrl];
        NSLog(@"%ld", data.length);
        
//        NSURLSessionUploadTask *task = [[NSURLSession sharedSession] uploadTaskWithRequest:req fromFile:fileUrl completionHandler:^(NSData *_Nullable data, NSURLResponse *_Nullable response, NSError *_Nullable error) {
//            if (error == nil) {
//                NSLog(@"上传完成");
//            } else {
//                NSLog(@"上传失败 error:%@", error);
//            }
//        }];
//        [task resume];
    });
}

- (IBAction)clearAllLogs:(id)sender
{
    loganClearAllLogs();
}

/**
 用户行为日志

 @param eventType 事件类型
 @param label 描述
 */
- (void)eventLogType:(NSInteger)eventType forLabel:(NSString *)label {
    NSMutableString *s = [NSMutableString string];
//    [s appendFormat:@"%d\t", (int)eventType];
//    [s appendFormat:@"%@\t", label];
    logan(LoganTypeAction, label);
}
@end
