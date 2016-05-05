//
//  WNDiskCache.m
//  WannaCache
//
//  Created by X-Liang on 16/4/29.
//  Copyright © 2016年 X-Liang. All rights reserved.
//

#import "WNDiskCache.h"
#import <pthread.h>
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0
#import <UIKit/UIKit.h>
#endif

static NSString * const WannaDiskCachePrefix = @"com.wanna.WannaDiskCaches";
static NSString * const WannaDiskCacheSharedName = @"WannaDiskCacheShared";

#define Lock(_lock) (pthread_mutex_lock(&_lock))
#define Unlock(_lock) (pthread_mutex_unlock(&_lock))

#define AsyncOption(option) \
dispatch_async(_asyncQueue, ^{\
option;\
});

#define WNDiskCacheError(error) if (error) { NSLog(@"%@ (%d) ERROR: %@", \
[[NSString stringWithUTF8String:__FILE__] lastPathComponent], \
__LINE__, [error localizedDescription]); }

#define LockBlock(option) \
Lock(_lock);\
option;\
Unlock(_lock);\

@interface WNBackgroundTask : NSObject

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0 && !TARGET_OS_WATCH
@property (atomic, assign) UIBackgroundTaskIdentifier taskIdentifier;
#endif
+ (instancetype)start;
- (void)end;
@end

@interface WNDiskCache ()
@property (assign) NSUInteger byteCount;
@property (nonatomic, strong) NSURL *cacheURL;
#if OS_OBJECT_USE_OBJC  // iOS 6 之后 SDK 支持 GCD ARC, 不需要再 Dealloc 中 release
@property (nonatomic, strong) dispatch_queue_t asyncQueue;
#else
@property (nonatomic, assign) dispatch_queue_t asyncQueue;
#endif
@property (nonatomic, strong) NSMutableDictionary *dates;
@property (nonatomic, strong) NSMutableDictionary *sizes;
@end

@implementation WNDiskCache {
    pthread_mutex_t _lock;
}

@synthesize willAddObjectBlock = _willAddObjectBlock;
@synthesize willRemoveObjectBlock = _willRemoveObjectBlock;
@synthesize willRemoveAllObjectsBlock = _willRemoveAllObjectsBlock;
@synthesize didAddObjectBlock = _didAddObjectBlock;
@synthesize didRemoveObjectBlock = _didRemoveObjectBlock;
@synthesize didRemoveAllObjectsBlock = _didRemoveAllObjectsBlock;
@synthesize byteLimit = _byteLimit;
@synthesize byteCount = _byteCount;
@synthesize ttlCache = _ttlCache;
@synthesize ageLimit = _ageLimit;
@synthesize writingProtectionOption = _writingProtectionOption;

- (void)dealloc {
#if !OS_OBJECT_USE_OBJC
    dispatch_release(_asyncQueue);
    _asyncQueue = nil;
#endif
    pthread_mutex_destroy(&_lock);
}

- (instancetype)init {
    @throw [NSException exceptionWithName:@"必须指定一个名称"
                                   reason:@"WNDiskCache 必须指定一个名称才能被创建, 请调用 initWithName:instead 方法"
                                 userInfo: nil];
    return [self initWithName:@""];
}

- (instancetype)initWithName:(NSString *)name {
    return [self initWithName:name rootPath:[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0]];
}

- (instancetype __nullable)initWithName:(NSString * __nullable)name rootPath:(NSString *__nullable)rootPath {
    if (!name) {
        return nil;
    }
    if (self = [super init]) {
        _name = [name copy];
        _asyncQueue = dispatch_queue_create([[NSString stringWithFormat:@"%@ Asynchronous Queue", WannaDiskCachePrefix] UTF8String], DISPATCH_QUEUE_CONCURRENT);
        _byteCount = 0;
        _byteLimit = 0;
        _ageLimit = 0.0;
        
#if TARGET_OS_IPHONE
        // the file is not stored in an encrypted format and may be accessed at boot time and while the device is unlocked.
        _writingProtectionOption = NSDataWritingFileProtectionNone;
#endif
        _dates = [NSMutableDictionary dictionary];
        _sizes = [NSMutableDictionary dictionary];
        
        NSString *pathComponent = [NSString stringWithFormat:@"%@.%@",WannaDiskCachePrefix, _name];
        _cacheURL = [NSURL fileURLWithPathComponents:@[rootPath, pathComponent]];
        
        Lock(_lock);
        dispatch_async(_asyncQueue, ^{
            [self createCacheDirectory];
            [self initializeDiskProperties];
            
            Unlock(_lock);
            
        });
    }
    return self;
}

+ (instancetype)sharedCache {
    static WNDiskCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[self alloc] initWithName:WannaDiskCacheSharedName];
    });
    return cache;
}

#pragma mark - Private Method
- (NSURL *)encodedFileURLForKey:(NSString *)key {
    if (![key length]) {
        return nil;
    }
    return [_cacheURL URLByAppendingPathComponent:[self encodedString:key]];
}

- (NSString *)keyForEncodeFileURL:(NSURL *)url {
    NSString *fileName = [url lastPathComponent];
    if (!fileName) {
        return nil;
    }
    return [self decodedString:fileName];
}

- (NSString *)encodedString:(NSString *)string {
    if (![string length]) {
        return nil;
    }
    
    if ([string respondsToSelector:@selector(stringByAddingPercentEncodingWithAllowedCharacters:)]) {
        return [string stringByAddingPercentEncodingWithAllowedCharacters:[[NSCharacterSet characterSetWithCharactersInString:@".:/%"] invertedSet]];
    } else {
        CFStringRef static const charToEscape = CFSTR(".:/%");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        CFStringRef escapedString = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                                            (__bridge CFStringRef)string,
                                                                            NULL,
                                                                            charToEscape,
                                                                            kCFStringEncodingUTF8);
#pragma clang diagnositc pop
        return (__bridge_transfer NSString *)escapedString;
    }
}

- (NSString *)decodedString:(NSString *)string {
    if (![string length]) {
        return @"";
    }
    if ([string respondsToSelector:@selector(stringByRemovingPercentEncoding)]) {
        return [string stringByRemovingPercentEncoding];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        CFStringRef unescapedString = CFURLCreateStringByReplacingPercentEscapesUsingEncoding(kCFAllocatorDefault,
                                                                                              (__bridge CFStringRef)string,
                                                                                              CFSTR(""),
                                                                                              kCFStringEncodingUTF8);
#pragma clang diagnostic pop
        return (__bridge_transfer NSString *)unescapedString;
    }
}

#pragma mark - Private Task Methods
+ (dispatch_queue_t)sharedTrashQueue {
    static dispatch_queue_t trashQueue;
    static dispatch_once_t predicate;
    dispatch_once(&predicate, ^{
        //???: GCD
        NSString *queueName = [[NSString alloc] initWithFormat:@"%@.trash",WannaDiskCachePrefix];
        trashQueue = dispatch_queue_create([queueName UTF8String], DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(trashQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));
    });
    return trashQueue;
}

+ (NSURL *)sharedTrashURL {
    static NSURL *sharedTrashURL;
    static dispatch_once_t predicate;
    dispatch_once(&predicate, ^{
        sharedTrashURL = [[[NSURL alloc] initFileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:WannaDiskCachePrefix isDirectory:YES];
        if ([[NSFileManager defaultManager] fileExistsAtPath:[sharedTrashURL path]]) {
            NSError *error = nil;
            //???:
            [[NSFileManager defaultManager] createDirectoryAtURL:sharedTrashURL
                                     withIntermediateDirectories:YES
                                                      attributes:nil
                                                           error:&error];
            WNDiskCacheError(error);
        }
    });
    return sharedTrashURL;
}

+ (BOOL)moveItemAtURLToTrash:(NSURL *)itemURL {
    // 如果要移除的 trash 目录下没有内容, 返回 NO
    if (![[NSFileManager defaultManager] fileExistsAtPath:[itemURL path]]) {
        return NO;
    }
    
    NSError *error = nil;
    //???:
    NSString *uniqueString = [[NSProcessInfo processInfo] globallyUniqueString];
    NSURL *uniqueTrashURL = [[WNDiskCache sharedTrashURL] URLByAppendingPathComponent:uniqueString];
    BOOL moved = [[NSFileManager defaultManager] moveItemAtURL:itemURL
                                                         toURL:uniqueTrashURL
                                                         error:&error];
    WNDiskCacheError(error);
    return moved;
}

+ (void)emptyTrash {
    dispatch_async([self sharedTrashQueue], ^{
        WNBackgroundTask *task = [WNBackgroundTask start];
        
        NSError *searchTrashedItemsError = nil;
        //???:
        NSArray *trashedItems = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[self sharedTrashURL]
                                                              includingPropertiesForKeys:nil
                                                                                 options:0
                                                                                   error:&searchTrashedItemsError];
        WNDiskCacheError(searchTrashedItemsError);
        [trashedItems enumerateObjectsUsingBlock:^(NSURL *trashedItemURL, NSUInteger idx, BOOL * _Nonnull stop) {
            NSError *removeTrashedItemError = nil;
            [[NSFileManager defaultManager] removeItemAtURL:trashedItemURL error:&removeTrashedItemError];
            WNDiskCacheError(removeTrashedItemError);
        }];
        
        [task end];
    });
}

#pragma mark - Private Queue Method
- (BOOL)createCacheDirectory {
    if ([[NSFileManager defaultManager] fileExistsAtPath:[_cacheURL path]]) {
        return NO;
    }
    NSError *error = nil;
    //???:
    BOOL success = [[NSFileManager defaultManager] createDirectoryAtURL:_cacheURL
                                            withIntermediateDirectories:YES
                                                             attributes:nil
                                                                  error:&error];
    WNDiskCacheError(error);
    return success;
}

- (void)initializeDiskProperties {
    __block NSUInteger byteCount = 0;
    //???:
    NSArray *keys = @[NSURLContentModificationDateKey, NSURLTotalFileAllocatedSizeKey];
    
    __block NSError *error = nil;
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:_cacheURL
                                                   includingPropertiesForKeys:keys
                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                        error:&error];
    WNDiskCacheError(error);
    
    [files enumerateObjectsUsingBlock:^(NSURL * _Nonnull fileURL, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *key = [self keyForEncodeFileURL:fileURL];
        error = nil;
        NSDictionary *dic = [fileURL resourceValuesForKeys:keys error:&error];
        NSDate *date = [dic objectForKey:NSURLContentModificationDateKey];
        if (date && key) {
            [_dates setObject:date forKey:key];
        }
        
        NSNumber *fileSize = [dic objectForKey:NSURLTotalFileAllocatedSizeKey];
        if (fileSize) {
            [_sizes setObject:fileSize forKey:key];
            byteCount += [fileSize unsignedIntegerValue];
        }
        if (byteCount > 0) {
            self.byteCount = byteCount;  //???: aotomic
        }
    }];
}

- (BOOL)setFileModificationDate:(NSDate *)date forURL:(NSURL *)fileURL {
    if (!date || !fileURL) {
        return NO;
    }
    
    NSError *error = nil;
    BOOL success = [[NSFileManager defaultManager] setAttributes:@{ NSFileModificationDate: date}
                                                    ofItemAtPath:[fileURL path]
                                                           error:&error];
    WNDiskCacheError(error);
    if (success) {
        NSString *key = [self keyForEncodeFileURL:fileURL];
        if (key) {
            [_dates setValue:date forKey:key];
        }
    }
    return success;
}

- (BOOL)removeFileAndExecuteBlocksForKey:(NSString *)key {
    NSURL *fileURL = [self encodedFileURLForKey:key];
    if (!fileURL || ![[NSFileManager defaultManager] fileExistsAtPath:[fileURL path]]) {
        return NO;
    }
    
    if (_willRemoveObjectBlock) {
        _willRemoveObjectBlock(self, key, nil, fileURL);
    }
    
    BOOL trashed = [WNDiskCache moveItemAtURLToTrash:fileURL];
    if (!trashed) {
        return NO;
    }
    
    NSNumber *byteSize = [_sizes objectForKey:key];
    if (byteSize) {
        //???: atomic
        self.byteCount = self.byteCount - [byteSize unsignedIntegerValue];
    }
    [_sizes removeObjectForKey:key];
    [_dates removeObjectForKey:key];
    
    if (_didRemoveObjectBlock) {
        _didRemoveObjectBlock(self, key, nil, fileURL);
    }
    return YES;
}

- (void)trimDiskToSize:(NSUInteger)trimByteCount {
    if (_byteCount <= trimByteCount) {
        return;
    }
    NSArray *keysSortedBySize = [_sizes keysSortedByValueUsingSelector:@selector(compare:)];
    // 大的先被移除
    [keysSortedBySize enumerateObjectsWithOptions:NSEnumerationReverse
                                       usingBlock:^(NSString *key, NSUInteger idx, BOOL * _Nonnull stop) {
                                           [self removeFileAndExecuteBlocksForKey:key];
                                           if (_byteCount <= trimByteCount) {
                                               *stop = YES;
                                           }
                                       }];
}

- (void)trimDiskByDateToSize:(NSUInteger)trimByteCount {
    if (_byteCount <= trimByteCount) {
        return ;
    }
    NSArray *keysSortedByDate = [_dates keysSortedByValueUsingSelector:@selector(compare:)];
    [keysSortedByDate enumerateObjectsUsingBlock:^(NSString *key, NSUInteger idx, BOOL * _Nonnull stop) {
        [self removeFileAndExecuteBlocksForKey:key];
        if (_byteCount <= trimByteCount) {
            *stop = YES;
        }
    }];
}

- (void)trimDiskToDate:(NSDate *)date {
    NSArray *keysSortedByDate = (NSArray *)[[_dates keysSortedByValueUsingSelector:@selector(compare:)] reverseObjectEnumerator];
    NSInteger index = [self binarySearchEqualOrMoreDate:date fromKeys:keysSortedByDate];
    NSIndexSet *indexSets = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(index, keysSortedByDate.count - index)];
    [keysSortedByDate enumerateObjectsAtIndexes:indexSets
                                        options:NSEnumerationConcurrent
                                     usingBlock:^(NSString *key, NSUInteger idx, BOOL * _Nonnull stop) {
                                         if (key) {
                                             [self removeFileAndExecuteBlocksForKey:key];
                                         }
                                     }];
}

- (void)trimToAgeLimitRecursively {
    Lock(_lock);
    NSTimeInterval ageLimit = _ageLimit;
    Unlock(_lock);
    if (ageLimit == 0.0) {
        return;
    }
    
    Lock(_lock);
    NSDate *date = [[NSDate alloc] initWithTimeIntervalSinceNow:-ageLimit];
    [self trimDiskToDate:date];
    Unlock(_lock);
    __weak WNDiskCache *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_ageLimit * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong WNDiskCache *strongSelf = weakSelf;
        [strongSelf trimToAgeLimitRecursively];
    });
}

#pragma mark - Public Asynchronous Methods
// 执行一个 block 并为文件加锁
- (void)lockFileAccessWhileExecutingBlock:(void (^)(WNDiskCache *diskCache))block {
    __weak WNDiskCache *weakSelf = self;
    AsyncOption(
                __strong WNDiskCache *strongSlef = weakSelf;
                if (block) {
                    //???: 注意执行 block 的时候加锁
                    LockBlock(block(strongSlef));
                }
    );
}

- (void)objectForKey:(NSString *)key block:(WNDiskCacheObjectBlock)block {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSlef = weakSelf;
                NSURL *fileURL = nil;
                id <NSCoding> object = [strongSlef objectForKey:key fileURL:&fileURL];
                if (block) {
                    LockBlock(block(strongSlef, key, object, fileURL));
                }
    );
}

- (void)fileURLForKey:(NSString *)key block:(WNDiskCacheObjectBlock)block {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                NSURL *fileURL = [strongSelf fileURLForKey:key];
                if (block) {
                    LockBlock(block(strongSelf, key, nil, fileURL));
                }
    );
}

- (void)setObject:(id <NSCoding>)object forKey:(NSString *)key block:(WNDiskCacheObjectBlock)callBack {
    __weak typeof(self) weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                NSURL *fileURL = nil;
                [strongSelf setObject:object forKey:key fileURL:&fileURL];
                if (callBack) {
                    Lock(_lock);
                    callBack(strongSelf, key, object, fileURL);
                    Unlock(_lock);
                }
    );
}

- (void)removeObjectForKey:(NSString *)key block:(WNDiskCacheObjectBlock)block {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                NSURL *fileURL = nil;
                [strongSelf removeObjectForKey:key fileURL:&fileURL];
                if (block) {
                    Lock(_lock);
                    block(strongSelf, key, nil, fileURL);
                    Unlock(_lock);
                }
    );
}

- (void)trimToSize:(NSUInteger)trimByteCount block:(WNDiskCacheBlcok)block {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                [strongSelf trimToSize:trimByteCount];
                if (block) {
                    Lock(_lock);
                    block(strongSelf);
                    Unlock(_lock);
                }
    );
}

- (void)trimToDate:(NSDate *)trimDate block:(WNDiskCacheBlcok)block {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                [strongSelf trimToDate:trimDate];
                if (block) {
                    Lock(_lock);
                    block(strongSelf);
                    Unlock(_lock);
                }
    );
}

- (void)trimByDateToSize:(NSUInteger)trimByteCount block:(WNDiskCacheBlcok)callBack {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                [strongSelf trimDiskByDateToSize:trimByteCount];
                if (callBack) {
                    Lock(_lock);
                    callBack(strongSelf);
                    Unlock(_lock);
                }
    );
}

- (void)removeAllObjects:(WNDiskCacheBlcok)callBack {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                [strongSelf removeAllObjects];
                if (callBack) {
                    Lock(_lock);
                    callBack(strongSelf);
                    Lock(_lock);
                }
    );
}

- (void)enumerateObjectsWithBlock:(WNDiskCacheObjectBlock)option completionBlock:(WNDiskCacheBlcok)completionBlock {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                [strongSelf enumerateObjectsWithBlock:option];
                if (completionBlock) {
                    Lock(_lock);
                    completionBlock(strongSelf);
                    Unlock(_lock);
                }
    );
}

#pragma mark - Public Synchronous Method
- (void)synchronouslyLockFileAccessWhileExecutingBlock:(void (^)(WNDiskCache *cache))callBack {
    if (callBack) {
        Lock(_lock);
        callBack(self);
        Unlock(_lock);
    }
}

- (__nullable id<NSCoding>)objectForKey:(NSString *)key {
    return [self objectForKey:key fileURL:nil];
}

- (id)objectForKeyedSubscript:(NSString *)key {
    return [self objectForKey:key];
}

//???:
- (__nullable id<NSCoding>)objectForKey:(NSString *)key fileURL:(NSURL **)outFileURL {
    NSDate *now = [NSDate date];
    if (!key) {
        return nil;
    }
    
    id <NSCoding>object = nil;
    NSURL *fileURL = nil;
    
    Lock(_lock);
    fileURL = [self encodedFileURLForKey:key];
    object = nil;
    if ([[NSFileManager defaultManager] fileExistsAtPath:[fileURL path]] &&
        (!self->_ttlCache ||
         self->_ageLimit <= 0 ||
         fabs([[_dates objectForKey:key] timeIntervalSinceDate:now]) < self->_ageLimit)) {
            @try {
                //???:
                object = [NSKeyedUnarchiver unarchiveObjectWithFile:[fileURL path]];
            } @catch (NSException *exception) {
                NSError *error = nil;
                [[NSFileManager defaultManager] removeItemAtPath:[fileURL path] error:&error];
            }
            if (!self->_ttlCache) {
                [self setFileModificationDate:now forURL:fileURL];
            }
    }
    Unlock(_lock);
    
    if (outFileURL) {
        *outFileURL = fileURL;
    }
    return object;
}

- (NSURL *)fileURLForKey:(NSString *)key {
    NSDate *now = [NSDate date];
    if (!key) {
        return nil;
    }
    NSURL *fileURL = nil;
    
    Lock(_lock);
    fileURL = [self encodedFileURLForKey:key];
    if ([[NSFileManager defaultManager] fileExistsAtPath:[fileURL path]]) {
        // 如果是 TTLCache 不要更新缓存修改时间
        if (!self->_ttlCache) {
            [self setFileModificationDate:now forURL:fileURL];
        }
    } else {
        fileURL = nil;
    }
    Unlock(_lock);
    return fileURL;
}

- (void)setObject:(id<NSCoding>)object forKey:(NSString *)key {
    [self setObject:object forKey:key fileURL:nil];
}

- (void)setObject:(id)object forKeyedSubscript:(NSString *)key {
    [self setObject:object forKey:key];
}

- (void)setObject:(id<NSCoding>)object forKey:(NSString *)key fileURL:(NSURL **)outFileURL {
    NSDate *now = [NSDate date];
    if (!key || !object) {
        return;
    }
    WNBackgroundTask *task = [WNBackgroundTask start];
#if TARGET_OS_IPHONE
    NSDataWritingOptions writingOptions = NSDataWritingAtomic | self.writingProtectionOption;
#else
    NSDataWritingOptions writingOptions = NSDataWritingAtomic;
#endif
    NSURL *fileURL = nil;
    Lock(_lock);
    
    fileURL = [self encodedFileURLForKey:key];
    if (self->_willAddObjectBlock) {
        self->_willAddObjectBlock(self, key, object, fileURL);
    }
    //???:
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:object];
    NSError *writeError = nil;
    BOOL written = [data writeToURL:fileURL options:writingOptions error:&writeError];
    WNDiskCacheError(writeError);
    if (written) {
        [self setFileModificationDate:now forURL:fileURL];
        
        NSError *error = nil;
        NSDictionary *values = [fileURL resourceValuesForKeys:@[ NSURLTotalFileAllocatedSizeKey ] error:&error];
        WNDiskCacheError(error);
        
        NSNumber *diskFileSize = [values objectForKey:NSURLTotalFileAllocatedSizeKey];
        if (diskFileSize) {
            NSNumber *prevDiskFileSize = [self->_sizes objectForKey:key];
            if (prevDiskFileSize) {
                self.byteCount = self->_byteCount - [prevDiskFileSize unsignedIntegerValue];
            }
            [self->_sizes setObject:diskFileSize forKey:key];
            self.byteCount = self->_byteCount + [diskFileSize unsignedIntegerValue];    // atomic
        }
        
        if (self->_byteLimit > 0 && self->_byteCount > self->_byteLimit) {
            [self trimByDateToSize:self->_byteLimit block:nil];
        }
    } else {
        fileURL = nil;
    }
    
    if (self->_didAddObjectBlock) {
        self->_didAddObjectBlock(self, key, object, written ? fileURL : nil);
    }
    
    Unlock(_lock);
    
    if (outFileURL) {
        *outFileURL = fileURL;
    }
    [task end];
}

- (void)removeObjectForKey:(NSString *)key {
    [self removeObjectForKey:key fileURL:nil];
}

- (void)removeObjectForKey:(NSString *)key fileURL:(NSURL **)outFileURL {
    if (!key) {
        return;
    }
    WNBackgroundTask *task = [WNBackgroundTask start];
    NSURL *fileURL = nil;
    Lock(_lock);
    fileURL = [self encodedFileURLForKey:key];
    [self removeFileAndExecuteBlocksForKey:key];
    Unlock(_lock);
    [task end];
    if (outFileURL) {
        *outFileURL = fileURL;
    }
}

- (void)trimToSize:(NSUInteger)trimByteCount {
    if (trimByteCount == 0) {
        [self removeAllObjects];
        return;
    }
    WNBackgroundTask *task = [WNBackgroundTask start];
    Lock(_lock);
    [self trimDiskToSize:trimByteCount];
    Unlock(_lock);
    [task end];
}

- (void)trimToDate:(NSDate *)date {
    if (!date) {
        return;
    }
    
    if ([date isEqualToDate:[NSDate distantPast]]) {
        [self removeAllObjects];
        return;
    }
    
    WNBackgroundTask *task = [WNBackgroundTask start];
    Lock(_lock);
    [self trimDiskToDate:date];
    Unlock(_lock);
    [task end];
}

- (void)trimByDateToSize:(NSUInteger)trimSize {
    if (trimSize == 0) {
        [self removeAllObjects];
        return;
    }
    
    WNBackgroundTask *task = [WNBackgroundTask start];
    Lock(_lock);
    [self trimDiskByDateToSize:trimSize];
    Unlock(_lock);
    [task end];
}

- (void)removeAllObjects {
    WNBackgroundTask *task = [WNBackgroundTask start];
    Lock(_lock);
    if (self->_willRemoveAllObjectsBlock) {
        self->_willRemoveAllObjectsBlock(self);
    }
    [WNDiskCache moveItemAtURLToTrash:self->_cacheURL];
    [WNDiskCache emptyTrash];
    [self createCacheDirectory];
    [self->_dates removeAllObjects];
    [self->_sizes removeAllObjects];
    self.byteCount = 0; //atomic
    if (self->_didRemoveAllObjectsBlock) {
        self->_didRemoveAllObjectsBlock(self);
    }
    Unlock(_lock);
    [task end];
}

- (void)enumerateObjectsWithBlock:(WNDiskCacheObjectBlock)block {
    if (!block) {
        return;
    }
    WNBackgroundTask *task = [WNBackgroundTask start];
    Lock(_lock);
    NSDate *now = [NSDate date];
    NSArray *keysSortedByDate = [self->_dates keysSortedByValueUsingSelector:@selector(compare:)];
    [keysSortedByDate enumerateObjectsUsingBlock:^(NSString *key, NSUInteger idx, BOOL * _Nonnull stop) {
        NSURL *fileURL = [self encodedFileURLForKey:key];
        if (!self->_ttlCache ||
            self->_ageLimit <= 0 ||
            fabs([[_dates objectForKey:key] timeIntervalSinceDate:now]) < self->_ageLimit) {
            block(self, key, nil, fileURL);
        }
    }];
    Unlock(_lock);
    [task end];
}

- (WNDiskCacheObjectBlock)willAddObjectBlock {
    WNDiskCacheObjectBlock block = nil;
    Lock(_lock);
    block = _willAddObjectBlock;
    Unlock(_lock);
    return block;
}

- (void)setWillAddObjectBlock:(WNDiskCacheObjectBlock)willAddObjectBlock {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                if (!strongSelf) return ;
                Lock(_lock);
                strongSelf->_willAddObjectBlock = willAddObjectBlock;
                Unlock(_lock);
    );
}

- (WNDiskCacheBlcok)willRemoveAllObjectsBlock {
    WNDiskCacheBlcok block = nil;
    Lock(_lock);
    block = _willRemoveAllObjectsBlock;
    Unlock(_lock);
    return block;
}

- (void)setWillRemoveAllObjectsBlock:(WNDiskCacheBlcok)willRemoveAllObjectsBlock {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                if (!strongSelf) {
                    return ;
                }
                Lock(_lock);
                strongSelf->_willRemoveAllObjectsBlock = willRemoveAllObjectsBlock;
                Unlock(_lock);
    );
}

- (WNDiskCacheObjectBlock)willRemoveObjectBlock {
    WNDiskCacheObjectBlock block = nil;
    Lock(_lock);
    block = _willRemoveObjectBlock;
    Unlock(_lock);
    return block;
}

- (void)setWillRemoveObjectBlock:(WNDiskCacheObjectBlock)willRemoveObjectBlock {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                if (!strongSelf) return ;
                Lock(_lock);
                strongSelf->_willRemoveObjectBlock = willRemoveObjectBlock;
                Unlock(_lock);
    );
}

- (WNDiskCacheObjectBlock)didAddObjectBlock {
    WNDiskCacheObjectBlock block = nil;
    Lock(_lock);
    block = _didAddObjectBlock;
    Unlock(_lock);
    return block;
}

- (void)setDidAddObjectBlock:(WNDiskCacheObjectBlock)didAddObjectBlock {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                if (!strongSelf) return ;
                Lock(_lock);
                strongSelf->_didAddObjectBlock = didAddObjectBlock;
                Unlock(_lock);
    );
}

- (WNDiskCacheObjectBlock)didRemoveObjectBlock {
    WNDiskCacheObjectBlock block = nil;
    Lock(_lock);
    block = _didRemoveObjectBlock;
    Unlock(_lock);
    return block;
}

- (void)setDidRemoveObjectBlock:(WNDiskCacheObjectBlock)didRemoveObjectBlock {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                if (!strongSelf) return ;
                Lock(_lock);
                strongSelf->_didRemoveObjectBlock = didRemoveObjectBlock;
                Unlock(_lock);
    );
}

- (WNDiskCacheBlcok)didRemoveAllObjectsBlock {
    WNDiskCacheBlcok block = nil;
    Lock(_lock);
    block = _didRemoveAllObjectsBlock;
    Unlock(_lock);
    return block;
}

- (void)setDidRemoveAllObjectsBlock:(WNDiskCacheBlcok)didRemoveAllObjectsBlock {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                if (!strongSelf) return ;
                Lock(_lock);
                strongSelf->_didRemoveAllObjectsBlock = didRemoveAllObjectsBlock;
                Unlock(_lock);
                );
}

- (NSUInteger)byteLimit {
    NSUInteger byteLimit;
    Lock(_lock);
    byteLimit = _byteLimit;
    Unlock(_lock);
    return byteLimit;
}

- (void)setByteLimit:(NSUInteger)byteLimit {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                if (!strongSelf) return ;
                Lock(_lock);
                strongSelf->_byteLimit = byteLimit;
                Unlock(_lock);
                );
}

- (NSTimeInterval)ageLimit {
    NSTimeInterval ageLimit;
    Lock(_lock);
    ageLimit = _ageLimit;
    Unlock(_lock);
    return ageLimit;
}

- (void)setAgeLimit:(NSTimeInterval)ageLimit {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                if (!strongSelf) return ;
                Lock(_lock);
                strongSelf->_ageLimit = ageLimit;
                Unlock(_lock);
                [strongSelf trimToAgeLimitRecursively];
                );
}

- (BOOL)isTTLCache {
    BOOL isTTLCache;
    Lock(_lock);
    isTTLCache = _ttlCache;
    Unlock(_lock);
    return isTTLCache;
}

- (void)setTtlCache:(BOOL)ttlCache {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                if (!strongSelf) return ;
                Lock(_lock);
                strongSelf->_ttlCache = ttlCache;
                Unlock(_lock);
                );
}

#if TARGET_OS_IPHONE
- (NSDataWritingOptions)writingProtectionOption {
    NSDataWritingOptions option;
    Lock(_lock);
    option = _writingProtectionOption;
    Unlock(_lock);
    return option;
}

- (void)setWritingProtectionOption:(NSDataWritingOptions)writingProtectionOption {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                if (!strongSelf) return ;
                Lock(_lock);
                strongSelf->_writingProtectionOption = writingProtectionOption;
                Unlock(_lock);
                );
}

#endif

#pragma mark -
/**
 *  二分搜索第一个大于等于 date 的位置
 *
 *  @param date 指定的 date
 *  @param keys date 数组
 *
 *  @return 第一个大于等于 date 的位置
 */
- (NSUInteger)binarySearchEqualOrMoreDate:(NSDate *)date fromKeys:(NSArray *)keys {
    NSUInteger begin = 0, end = keys.count;
    while (begin <= end) {
        NSUInteger mid = (begin + end) * .5f;
        // date 大于 中间值成递增状 date < keys[mid]
        if ([date compare:keys[mid]] == NSOrderedAscending) {
            end = mid - 1;
        } else if ([date compare:keys[mid]] == NSOrderedDescending) {   // date > keys[mid]
            begin = mid + 1;
        }
        
    }
    return begin;
}

@end


@implementation WNBackgroundTask

+ (BOOL)isAppExtension {
    static BOOL isExtension;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary *extensionDictionary = [[NSBundle mainBundle] infoDictionary][@"NSExtension"];
        isExtension = [extensionDictionary isKindOfClass:[NSDictionary class]];
    });
    return isExtension;
}

- (instancetype)init {
    if (self = [super init]) {
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0 && !TARGET_OS_WATCH
        _taskIdentifier = UIBackgroundTaskInvalid;
#endif
    }
    return self;
}

+ (instancetype)start {
    WNBackgroundTask *task = nil;
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0 && !TARGET_OS_WATCH
    if ([self.class isAppExtension]) {
        return task;
    }
    UIApplication *sharedApplication = [UIApplication performSelector:@selector(sharedApplication)];
    // 开始指定后台任务, 并记录当前的任务 id
    task.taskIdentifier = [sharedApplication beginBackgroundTaskWithExpirationHandler:^{
        // 记录当前执行的任务 id
        UIBackgroundTaskIdentifier taskId = task.taskIdentifier;
        // 将任务的任务 id 置为无效
        task.taskIdentifier = UIBackgroundTaskInvalid;
        // 结束指定的任务 id 对应的任务
        [sharedApplication endBackgroundTask:taskId];
    }];
#endif
    return task;
}

- (void)end {
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0 && !TARGET_OS_WATCH
    if ([self.class isAppExtension]) {
        return;
    }
    
    UIBackgroundTaskIdentifier taskId = self.taskIdentifier;
    self.taskIdentifier = UIBackgroundTaskInvalid;
    
    UIApplication *sharedApplication = [UIApplication performSelector:@selector(sharedApplication)];
    [sharedApplication endBackgroundTask:taskId];
#endif
}

@end
