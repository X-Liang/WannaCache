//
//  WNMemoryCache.m
//  WannaCache
//
//  Created by X-Liang on 16/4/27.
//  Copyright © 2016年 X-Liang. All rights reserved.
//

#import "WNMemoryCache.h"
#import <pthread.h>

static NSString * const WannaMemoryCachePrefix = @"com.wanna.WannaMemoryCaches";

#define Lock(_lock) (pthread_mutex_lock(&_lock))
#define Unlock(_lock) (pthread_mutex_unlock(&_lock))

#define AsyncOption(option) \
dispatch_async(_concurrentQueue, ^{\
    option;\
});

@interface WNMemoryCache ()
#if OS_OBJECT_USE_OBJC  // iOS 6 之后 SDK 支持 GCD ARC, 不需要再 Dealloc 中 release
@property (nonatomic, strong) dispatch_queue_t concurrentQueue;
#else
@property (nonatomic, assign) dispatch_queue_t concurrentQueue;
#endif
/**
 *  缓存数据, key可以为 URL, value 为网络数据
 */
@property (nonatomic, strong) NSMutableDictionary *dictionary;
/**
 *  每个缓存数据的最近访问时间
 */
@property (nonatomic, strong) NSMutableDictionary *dates;
/**
 *  记录每个缓存的花费
 */
@property (nonatomic, strong) NSMutableDictionary *costs;
@end

@implementation WNMemoryCache {
    pthread_mutex_t _lock;
}

@synthesize ageLimit = _ageLimit;
@synthesize costLimit = _costLimit;
@synthesize totalCost = _totalCost;
@synthesize ttlCache = _ttlCache;
@synthesize willAddObjectBlock = _willAddObjectBlock;
@synthesize willRemoveObjectBlock = _willRemoveObjectBlock;
@synthesize willRemoveAllObjectsBlock = _willRemoveAllObjectsBlock;
@synthesize didAddObjectBlock = _didAddObjectBlock;
@synthesize didRemoveObjectBlock = _didRemoveObjectBlock;
@synthesize didRemoveAllObjectsBlock = _didRemoveAllObjectsBlock;
@synthesize didEnterBackgroundBlock = _didEnterBackgroundBlock;
@synthesize didReceiveMemoryWarningBlock = _didReceiveMemoryWarningBlock;

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
#if !OS_OBJECT_USE_OBJC
    dispatch_release(_concurrentQueue);
    _concurrentQueue = nil;
#endif
    pthread_mutex_destroy(&_lock);
}

- (instancetype)init {
    if (self = [super init]) {
        NSString *queueName = [NSString stringWithFormat:@"%@.%p",WannaMemoryCachePrefix,self];
        // 以指定的名称, 创建并发队列, 用于异步缓存数据
        _concurrentQueue = dispatch_queue_create([queueName UTF8String], DISPATCH_QUEUE_CONCURRENT);
        
        _removeAllObjectOnMemoryWoring = YES;
        _removeAllObjectOnEnteringBackground = YES;
        
        _dictionary = [NSMutableDictionary dictionary];
        _dates = [NSMutableDictionary dictionary];
        _costs = [NSMutableDictionary dictionary];
        
        _willAddObjectBlock = nil;
        _willRemoveObjectBlock = nil;
        _willRemoveAllObjectsBlock = nil;
        
        _didAddObjectBlock = nil;
        _didRemoveObjectBlock = nil;
        _didRemoveAllObjectsBlock = nil;
        
        _didReceiveMemoryWarningBlock = nil;
        _didEnterBackgroundBlock = nil;
        
        _ageLimit = 0.0;
        _costLimit = 0;
        _totalCost = 0;

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_0 && !TARGET_OS_WATCH
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didReceiveEnterBackgroundNotification:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didReceiveMemoryWarningNotification:)
                                                     name:UIApplicationDidReceiveMemoryWarningNotification
                                                   object:nil];

#endif
    }
    return self;
}

+ (instancetype)shareInstance {
    static WNMemoryCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[self alloc] init];
    });
    return cache;
}

#pragma mark - Notify Method
/**
 *  收到内存警告操作
 */
- (void)didReceiveMemoryWarningNotification:(NSNotification *)notify {
    if (self.removeAllObjectOnMemoryWoring) {
        [self removeAllObject:nil];
    }
    
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                if (!strongSelf) return ;
                Lock(_lock);
                WNMemoryCacheBlcok didReceiveMemoryWarningBlock = strongSelf->_didReceiveMemoryWarningBlock;
                Unlock(_lock);
                if (didReceiveMemoryWarningBlock) {
                    didReceiveMemoryWarningBlock(strongSelf);
                }
    );
}

/**
 *  程序进入后台操作
 */
- (void)didReceiveEnterBackgroundNotification:(NSNotification *)notify {
    if (self.removeAllObjectOnEnteringBackground) {
        [self removeAllObject:nil];
    }
    __weak typeof(self)weakSelf = self;
    AsyncOption(
               __strong typeof(weakSelf)strongSelf = weakSelf;
               if (!strongSelf) return ;
               Lock(_lock);
               WNMemoryCacheBlcok didEnterBackgroundBlock = strongSelf->_didEnterBackgroundBlock;
               Unlock(_lock);
               if (didEnterBackgroundBlock) {
                   didEnterBackgroundBlock(strongSelf);
               }
    );

}

#pragma mark - Thread Safety Private Method
/**
 *  线程安全, 移除指定 key 的缓存, 并执行回调
 *
 *  @param key 指定的缓存 key
 */
- (void)removeObjectAndExectureBlockForKey:(NSString *)key {
    Lock(_lock);
    id object = _dictionary[key];
    NSNumber *cost = _costs[key];
    WNMemoryCacheObjectBlock willRemoveObjectBlock = _willRemoveObjectBlock;
    WNMemoryCacheObjectBlock didRemoveObjectBlcok = _didRemoveObjectBlock;
    Unlock(_lock);
    
    if (willRemoveObjectBlock) {
        willRemoveObjectBlock(self, key, object);
    }
    
    Lock(_lock);
    if (cost) {
        _totalCost -= [cost unsignedIntegerValue];
    }
    [_dictionary removeObjectForKey:key];
    [_costs removeObjectForKey:key];
    [_dates removeObjectForKey:key];
    Unlock(_lock);
    if (didRemoveObjectBlcok) {
        didRemoveObjectBlcok(self, key, object);
    }
}

/**
 *  使所有的缓存时间 <= date
 *
 *  @param date 指定的缓存时间
 */
- (void)trimMemoryToDate:(NSDate *)date {
    Lock(_lock);
    NSArray *sortKeyByDate = (NSArray *)[[_dates keysSortedByValueUsingSelector:@selector(compare:)] reverseObjectEnumerator];
    Unlock(_lock);
    NSUInteger index = [self binarySearchEqualOrMoreDate:date fromKeys:sortKeyByDate];
    
    NSIndexSet *indexSets = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, index)];
    [sortKeyByDate enumerateObjectsAtIndexes:indexSets
                                     options:NSEnumerationConcurrent
                                  usingBlock:^(NSString *key, NSUInteger idx, BOOL * _Nonnull stop) {
                                      if (key) {
                                          [self removeObjectAndExectureBlockForKey:key];
                                      }
                                  }];
}

/**
 *   根据缓存大小移除缓存到临界值, 缓存大的先被移除
 *
 *  @param limit 缓存临界值
 */
- (void)trimToCostLimit:(NSUInteger)limit {
    __block NSUInteger totalCost = 0;
    Lock(_lock);
    totalCost = _totalCost;
    NSArray *keysSortByCost = [_costs keysSortedByValueUsingSelector:@selector(compare:)];
    Unlock(_lock);
    
    if (totalCost <= limit) {
        return ;
    }
    // 将缓存从大到小移除, 直到小于指定的缓存临界值
    [keysSortByCost enumerateObjectsWithOptions:NSEnumerationReverse
                                     usingBlock:^(NSString *key, NSUInteger idx, BOOL * _Nonnull stop) {
                                         [self removeObjectAndExectureBlockForKey:key];
                                         Lock(_lock);
                                         totalCost = _totalCost;
                                         Unlock(_lock);
                                         if (totalCost <= limit) {
                                             *stop = YES;
                                         }
                                     }];
}

/**
 *  根据时间, 先移除时间最久的缓存, 直到缓存容量小于等于指定的 limit
 *  LRU(Last Recently Used): 最久未使用算法, 使用时间距离当前最就的将被移除
 */
- (void)trimCostByDateToCostLimit:(NSUInteger)limit {
    __block NSUInteger totalCost = 0;
    Lock(_lock);
    totalCost = _totalCost;
    NSArray *keysSortedByDate = [_dates keysSortedByValueUsingSelector:@selector(compare:)];
    Unlock(_lock);
    if (totalCost <= limit) {
        return;
    }
    
    // 先移除时间最长的缓存, date 时间小的
    [keysSortedByDate enumerateObjectsUsingBlock:^(NSString *key, NSUInteger idx, BOOL * _Nonnull stop) {
        [self removeObjectAndExectureBlockForKey:key];
        Lock(_lock);
        totalCost = _totalCost;
        Unlock(_lock);
        if (totalCost <= limit) {
            *stop = YES;
        }
    }];
}

/**
 *  递归检查并清除超过规定时间的缓存对象, TTL缓存操作
 */
- (void)trimToAgeLimitRecursively {
    Lock(_lock);
    NSTimeInterval ageLimit = _ageLimit;
    BOOL ttlCache = _ttlCache;
    Unlock(_lock);
    if (ageLimit == 0.0 || !ttlCache) {
        return ;
    }
    // 从当前时间开始, 往前推移 ageLimit(内存缓存对象允许存在的最大时间)
    NSDate *trimDate = [NSDate dateWithTimeIntervalSinceNow:-ageLimit];
    // 将计算得来的时间点之前的数据清除, 确保每个对象最大存在 ageLimit 时间
    [self trimMemoryToDate:trimDate];
    
    // ageLimit 之后在递归执行
    __weak typeof(self)weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ageLimit * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf)strongSelf = weakSelf;
        [strongSelf trimToAgeLimitRecursively];
    });
}

#pragma mark - Async Method Public Method

/**
 *  移除所有的数据
 *
 *  @param callBack 回调
 */
- (void)removeAllObject:(WNMemoryCacheBlcok)callBack {
    __weak typeof(self)weakSelf = self;
    // 异步移除所有数据
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                [strongSelf removeAllObjects];
                if (callBack) {
                    callBack(strongSelf);
                });
}


/**
 *  异步读取缓存的对象
 *
 *  @param key      缓存对象对应的 Key
 *  @param callBack 缓存对象读取成功后回调
 */
- (void)objectForKey:(NSString *)key block:(WNMemoryCacheObjectBlock)callBack {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                id object = [strongSelf objectForKey:key];
                if (callBack) {
                    callBack(strongSelf, key, object);
                }
    );
}

/**
 *  异步写入要缓存的对象
 *
 *  @param object   要缓存的对象
 *  @param key      缓存对象对应的 Key
 *  @param callBack 缓存成功后回调
 */
- (void)setObject:(id)object forKey:(NSString *)key blcok:(WNMemoryCacheObjectBlock)callBack {
    [self setObject: object
             forKey:key
           withCost:0
              blcok:callBack];
}
/**
 *  异步写入要缓存的对象
 *
 *  @param object   要缓存的对象
 *  @param key      缓存对象对应的 Key
 *  @param cost     缓存花费的代价
 *  @param callBack 缓存成功后回调
 */
- (void)setObject:(id)object forKey:(NSString *)key withCost:(NSUInteger)cost blcok:(WNMemoryCacheObjectBlock)callBack {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                [strongSelf setObject:object forKey:key withCost:cost];
                if(callBack) {
                    callBack(strongSelf, key, object);
                }
    );
}
/**
 *  异步移除指定 key 的缓存
 */
- (void)removeObjectForKey:(NSString *)key block:(WNMemoryCacheObjectBlock)callBack {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                [strongSelf removeObjectForKey:key];
                if (callBack) {
                    callBack(strongSelf, key, nil);
                }
    );
}

- (void)trimToDate:(NSDate *)trimDate block:(WNMemoryCacheBlcok)callBack {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                [strongSelf trimMemoryToDate:trimDate];
                if (callBack) callBack(strongSelf);
    );
}

- (void)trimToCostLimit:(NSUInteger)cost block:(WNMemoryCacheBlcok)callBack {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                [strongSelf trimToCostLimit:cost];
                if (callBack) callBack(strongSelf);
                );
}

- (void)trimCostByDateToCostLimit:(NSUInteger)costLimt blcok:(WNMemoryCacheBlcok)callBack {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                [strongSelf trimCostByDateToCostLimit:costLimt];
                if (callBack) callBack(strongSelf);
                );
}

- (void)removeAllObjects:(WNMemoryCacheBlcok)callBack {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                [strongSelf removeAllObjects];
                if (callBack) callBack(strongSelf);
                );
}

- (void)enumerateObjectsWithBlock:(WNMemoryCacheObjectBlock)optionBlock completionBlcok:(WNMemoryCacheBlcok)completionBlock {
    __weak typeof(self)weakSelf = self;
    AsyncOption(
                __strong typeof(weakSelf)strongSelf = weakSelf;
                [strongSelf enumerateObjectsWithBlock:optionBlock];
                if (completionBlock) {
                    completionBlock(strongSelf);
                });
}

#pragma mark - Sync Method
/**
 *  线程安全的缓存对象的读取操作, 所有关于缓存读取的操作都是调用该方法
 *
 *  @param key 要获得的缓存对应的 key
 *
 *  @return 缓存对象
 */
- (__nullable id)objectForKey:(NSString *)key {
    if (!key) {
        return nil;
    }
    
    NSDate *now = [NSDate date];
    Lock(_lock);
    id object = nil;
    /**
     *  如果指定了 TTL, 那么判断是否指定存活期, 如果指定存活期, 要判断对象是否在存活期内
     *  如果没有指定 TTL, 那么
     */
    if (!self->_ttlCache ||
        self->_ageLimit <= 0 ||
        fabs([_dates[key] timeIntervalSinceDate:now]) < self->_ageLimit) {
        object = _dictionary[key];
    }
    Unlock(_lock);
    if (object) {
        Lock(_lock);
        _dates[key] = now;
        Unlock(_lock);
    }
    return object;
}

/**
 *  线程安全的缓存存储操作, 所有的缓存写入都是调用该方法
 *
 *  @param object 要缓存的对象
 *  @param key    缓存对象对应的 Key
 *  @param cost   缓存的代价
 */
- (void)setObject:(id)object forKey:(NSString *)key withCost:(NSUInteger)cost {
    if (!key || !object) {
        return ;
    }
    Lock(_lock);
    WNMemoryCacheObjectBlock willAddObjectBlock = _willAddObjectBlock;
    WNMemoryCacheObjectBlock didAddObjectBlock = _didAddObjectBlock;
    NSUInteger coseLimit = _costLimit;
    Unlock(_lock);
    
    if (willAddObjectBlock) {
        willAddObjectBlock(self, key, object);
    }
    
    Lock(_lock);
    _dictionary[key] = object, _costs[key] = @(cost), _dates[key] = [NSDate date];
    _totalCost += cost;
    Unlock(_lock);
    
    if (didAddObjectBlock) {
        didAddObjectBlock(self, key, object);
    }
    
    if (coseLimit > 0) {
        [self trimCostByDateToCostLimit:coseLimit];
    }
}

- (void)enumerateObjectsWithBlock:(WNMemoryCacheObjectBlock)callBack {
    if (!callBack) {
        return;
    }
    Lock(_lock);
    NSDate *now = [NSDate date];
    NSArray *keysSortedByDate = [_dates keysSortedByValueUsingSelector:@selector(compare:)];
    // 在读取操作时, 不要在 block 中做写入操作, 会造成死锁
    // 时间越近的越先被执行
    __weak typeof(self)weakSelf = self;
    [keysSortedByDate enumerateObjectsWithOptions:NSEnumerationReverse
                                       usingBlock:^(NSString *key, NSUInteger idx, BOOL * _Nonnull stop) {
                                           __strong typeof(weakSelf)strongSelf = weakSelf;
                                           if (!strongSelf->_ttlCache ||
                                               strongSelf->_ageLimit < 0 ||
                                               fabs([_dates[key] timeIntervalSinceDate:now]) < strongSelf->_ageLimit) {
                                               callBack(strongSelf, key, _dates[key]);
                                           }
                                       }];
    Unlock(_lock);
}

- (void)removeObjectForKey:(NSString *)key {
    if (!key) {
        return;
    }
    [self removeObjectAndExectureBlockForKey:key];
}

- (void)removeAllObjects {
    // 加锁获得回调函数, 防止多线程时导致争夺出现回调不对应的情况
    Lock(_lock);
    WNMemoryCacheBlcok willRemoveAllObjectBlock = _willRemoveAllObjectsBlock;
    WNMemoryCacheBlcok didRemoveAllObjectBlcok = _didRemoveAllObjectsBlock;
    Unlock(_lock);
    
    if (willRemoveAllObjectBlock) {
        willRemoveAllObjectBlock(self);
    }
    
    // 移除全部数据
    Lock(_lock);
    [_dictionary removeAllObjects];
    [_costs removeAllObjects];
    [_dates removeAllObjects];
    _totalCost = 0;
    Unlock(_lock);
    
    if (didRemoveAllObjectBlcok) {
        didRemoveAllObjectBlcok(self);
    }
}

- (void)trimToDate:(NSDate *)date {
    if (!date) {
        return ;
    }
    // 指定时间为遥远的过去
    if ([date isEqualToDate:[NSDate distantPast]]) {
        [self removeAllObjects];
        return;
    }
    
    [self trimMemoryToDate:date];
}

- (void)trimToCost:(NSUInteger)cost {
    [self trimToCostLimit:cost];
}


#pragma mark - Protocol Method
- (void)setObject:(id)obj forKeyedSubscript:(NSString *)key {
    [self setObject:obj forKey:key withCost:0];
}

- (id)objectForKeyedSubscript:(NSString *)key {
    return [self objectForKey:key];
}

#pragma mark - 
- (WNMemoryCacheObjectBlock)willAddObjectBlock {
    Lock(_lock);
    WNMemoryCacheObjectBlock block = _willAddObjectBlock;
    Unlock(_lock);
    return block;
}

- (void)setWillAddObjectBlock:(WNMemoryCacheObjectBlock)willAddObjectBlock {
    Lock(_lock);
    _willAddObjectBlock = [willAddObjectBlock copy];
    Unlock(_lock);
}

- (WNMemoryCacheObjectBlock)willRemoveObjectBlock {
    Lock(_lock);
    WNMemoryCacheObjectBlock block = _willRemoveObjectBlock;
    Unlock(_lock);
    return block;
}

- (void)setWillRemoveObjectBlock:(WNMemoryCacheObjectBlock)willRemoveObjectBlock {
    Lock(_lock);
    _willRemoveObjectBlock = [willRemoveObjectBlock copy];
    Unlock(_lock);
}

- (WNMemoryCacheBlcok)willRemoveAllObjectsBlock {
    Lock(_lock);
    WNMemoryCacheBlcok block = _willRemoveAllObjectsBlock;
    Unlock(_lock);
    return block;
}

- (void)setWillRemoveAllObjectsBlock:(WNMemoryCacheBlcok)willRemoveAllObjectsBlock {
    Lock(_lock);
    _willRemoveAllObjectsBlock = [willRemoveAllObjectsBlock copy];
    Unlock(_lock);
}

- (WNMemoryCacheObjectBlock)didAddObjectBlock {
    Lock(_lock);
    WNMemoryCacheObjectBlock block = _didAddObjectBlock;
    Unlock(_lock);
    return block;
}

- (void)setDidAddObjectBlock:(WNMemoryCacheObjectBlock)didAddObjectBlock {
    Lock(_lock);
    _didAddObjectBlock = [didAddObjectBlock copy];
    Unlock(_lock);
}

- (WNMemoryCacheBlcok)didRemoveAllObjectsBlock {
    Lock(_lock);
    WNMemoryCacheBlcok block = _didRemoveAllObjectsBlock;
    Unlock(_lock);
    return block;
}

- (void)setDidRemoveAllObjectsBlock:(WNMemoryCacheBlcok)didRemoveAllObjectsBlock {
    Lock(_lock);
    _didRemoveAllObjectsBlock = [didRemoveAllObjectsBlock copy];
    Unlock(_lock);
}

- (WNMemoryCacheBlcok)didEnterBackgroundBlock {
    Lock(_lock);
    WNMemoryCacheBlcok block = _didEnterBackgroundBlock;
    Unlock(_lock);
    return block;
}

- (void)setDidEnterBackgroundBlock:(WNMemoryCacheBlcok)didEnterBackgroundBlock {
    Lock(_lock);
    _didEnterBackgroundBlock = [didEnterBackgroundBlock copy];
    Unlock(_lock);
}

- (WNMemoryCacheBlcok)didReceiveMemoryWarningBlock {
    Lock(_lock);
    WNMemoryCacheBlcok block = _didReceiveMemoryWarningBlock;
    Unlock(_lock);
    return block;
}

- (void)setDidReceiveMemoryWarningBlock:(WNMemoryCacheBlcok)didReceiveMemoryWarningBlock {
    Lock(_lock);
    _didReceiveMemoryWarningBlock = [didReceiveMemoryWarningBlock copy];
    Unlock(_lock);
}

- (NSTimeInterval)ageLimit {
    Lock(_lock);
    NSTimeInterval age = _ageLimit;
    Unlock(_lock);
    return age;
}

- (void)setAgeLimit:(NSTimeInterval)ageLimit {
    Lock(_lock);
    _ageLimit = ageLimit;
    if (ageLimit > 0) {
        _ttlCache = YES;
    }
    Unlock(_lock);
    [self trimToAgeLimitRecursively];
}

- (NSUInteger)costLimit {
    Lock(_lock);
    NSUInteger limit = _costLimit;
    Unlock(_lock);
    return limit;
}

- (void)setCostLimit:(NSUInteger)costLimit {
    Lock(_lock);
    _costLimit = costLimit;
    Unlock(_lock);
    if (costLimit > 0) {
        [self trimCostByDateToCostLimit:costLimit];
    }
}

- (NSUInteger)totalCost {
    Lock(_lock);
    NSUInteger cost = _totalCost;
    Unlock(_lock);
    return cost;
}

- (BOOL)isTTLCache {
    Lock(_lock);
    BOOL ttl = _ttlCache;
    Unlock(_lock);
    return ttl;
}

- (void)setTtlCache:(BOOL)ttlCache {
    Lock(_lock);
    _ttlCache = ttlCache;
    Unlock(_lock);
}

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
