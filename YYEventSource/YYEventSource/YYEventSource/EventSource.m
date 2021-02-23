//
//  AppDelegate.m
//  YYEventSource
//
//  Created by xiaotian on 2021/2/23.
//

#import "EventSource.h"
#import <CoreGraphics/CGBase.h>

static CGFloat const ES_RETRY_INTERVAL = 1.0;
static CGFloat const ES_DEFAULT_TIMEOUT = 300.0;

static NSString *const ESKeyValueDelimiter = @":";
static NSString *const ESEventSeparatorLFLF = @"\n\n";
static NSString *const ESEventSeparatorCRCR = @"\r\r";
static NSString *const ESEventSeparatorCRLFCRLF = @"\r\n\r\n";
static NSString *const ESEventKeyValuePairSeparator = @"\n";

static NSString *const ESEventDataKey = @"data";
static NSString *const ESEventIDKey = @"id";
static NSString *const ESEventEventKey = @"event";
static NSString *const ESEventRetryKey = @"retry";

@interface EventSource () <NSURLSessionDataDelegate> {
    BOOL wasClosed;
    dispatch_queue_t messageQueue;
    dispatch_queue_t connectionQueue;
}

@property (nonatomic, strong) NSURL *eventURL;
@property (nonatomic, strong) NSURLSession *eventSourceSession;
@property (nonatomic, strong) NSURLSessionDataTask *eventSourceTask;
@property (nonatomic, strong) NSMutableDictionary *listeners;
@property (nonatomic, assign) NSTimeInterval timeoutInterval;
@property (nonatomic, assign) NSTimeInterval retryInterval;
@property (nonatomic, strong) id lastEventID;
@property (nonatomic, strong) NSString *cacheData;

- (void)_open;
- (void)_dispatchEvent:(Event *)e;

@end

@implementation EventSource

+ (instancetype)eventSourceWithURL:(NSURL *)URL {
    return [[EventSource alloc] initWithURL:URL];
}

+ (instancetype)eventSourceWithURL:(NSURL *)URL timeoutInterval:(NSTimeInterval)timeoutInterval {
    return [[EventSource alloc] initWithURL:URL timeoutInterval:timeoutInterval];
}

- (instancetype)initWithURL:(NSURL *)URL {
    return [self initWithURL:URL timeoutInterval:ES_DEFAULT_TIMEOUT];
}

- (instancetype)initWithURL:(NSURL *)URL timeoutInterval:(NSTimeInterval)timeoutInterval {
    self = [super init];
    if (self) {
        _listeners = [NSMutableDictionary dictionary];
        _eventURL = URL;
        _timeoutInterval = timeoutInterval;
        _retryInterval = ES_RETRY_INTERVAL;
        _cacheData = @"";

        messageQueue = dispatch_queue_create("com.cwbrn.eventsource-queue", DISPATCH_QUEUE_SERIAL);
        connectionQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);

        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0 * NSEC_PER_SEC));
        dispatch_after(popTime, connectionQueue, ^(void){
            [self _open];
        });
    }
    return self;
}

+ (instancetype)eventSourceWithTask:(NSURLSessionDataTask *)task {
    return [[EventSource alloc] initWithTask:task];
}

- (instancetype)initWithTask:(NSURLSessionDataTask *)task {
    self = [super init];
    if (self) {
        _listeners = [NSMutableDictionary dictionary];
        _timeoutInterval = ES_DEFAULT_TIMEOUT;
        _retryInterval = ES_RETRY_INTERVAL;
        _cacheData = @"";

        messageQueue = dispatch_queue_create("com.cwbrn.eventsource-queue", DISPATCH_QUEUE_SERIAL);
        connectionQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);

        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0 * NSEC_PER_SEC));
        dispatch_after(popTime, connectionQueue, ^(void){
            [self _open];
        });
    }
    return self;
}

- (void)addEventListener:(NSString *)eventName handler:(EventSourceEventHandler)handler {
    if (self.listeners[eventName] == nil) {
        [self.listeners setObject:[NSMutableArray array] forKey:eventName];
    }
    
    [self.listeners[eventName] addObject:handler];
}

- (void)onMessage:(EventSourceEventHandler)handler {
    [self addEventListener:MessageEvent handler:handler];
}

- (void)onError:(EventSourceEventHandler)handler {
    [self addEventListener:ErrorEvent handler:handler];
}

- (void)onOpen:(EventSourceEventHandler)handler {
    [self addEventListener:OpenEvent handler:handler];
}

- (void)onReadyStateChanged:(EventSourceEventHandler)handler {
    [self addEventListener:ReadyStateEvent handler:handler];
}

- (void)close {
    wasClosed = YES;
    [self.eventSourceSession finishTasksAndInvalidate];
    [self.eventSourceTask cancel];
    [self.listeners removeAllObjects];
}

// -----------------------------------------------------------------------------------------------------------------------------------------

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
    if (httpResponse.statusCode == 200) {
        // Opened
        Event *e = [Event new];
        e.readyState = kEventStateOpen;

        [self _dispatchEvent:e type:ReadyStateEvent];
        [self _dispatchEvent:e type:OpenEvent];
    }

    if (completionHandler) {
        completionHandler(NSURLSessionResponseAllow);
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
    NSString *eventString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    self.cacheData = [self.cacheData stringByAppendingString:eventString];
    if (![self.cacheData hasSuffix:ESEventSeparatorLFLF]) {
        return;
    }
    NSArray *msgs = [self.cacheData componentsSeparatedByString:ESEventSeparatorLFLF];
    self.cacheData = @"";
    for (NSString *msg in msgs) {
        NSArray *lines = [msg componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        
        Event *event = [Event new];
        event.readyState = kEventStateOpen;
        
        for (NSString *line in lines) {
            
            if ([line hasPrefix:ESKeyValueDelimiter]) {
                continue;
            }
            @autoreleasepool {
                NSScanner *scanner = [NSScanner scannerWithString:line];
                scanner.charactersToBeSkipped = [NSCharacterSet whitespaceCharacterSet];//ignore whitespace.
                
                NSString *key, *value;
                [scanner scanUpToString:ESKeyValueDelimiter intoString:&key];//get [data:%^%#$] -> data
                [scanner scanString:ESKeyValueDelimiter intoString:nil];
                [scanner scanUpToCharactersFromSet:[NSCharacterSet newlineCharacterSet] intoString:&value];
                
                if (key && value) {
                    if ([key isEqualToString:ESEventEventKey]) {
                        event.eventType = value;
                    } else if ([key isEqualToString:ESEventDataKey]) {
                        event.eventType = MessageEvent;
                        if (event.data != nil) {
                            event.data = [event.data stringByAppendingFormat:@"\n%@", value];
                        } else {
                            event.data = value;
                        }
                    } else if ([key isEqualToString:ESEventIDKey]) {
                        event.eventId = value;
                        self.lastEventID = event.eventId;
                    } else if ([key isEqualToString:ESEventRetryKey]) {
                        self.retryInterval = [value doubleValue];
                    }
                }
            }
        }
        dispatch_async(messageQueue, ^{
            [self _dispatchEvent:event];
        });
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(nullable NSError *)error {
    self.eventSourceTask = nil;

    if (wasClosed) {
        return;
    }

    Event *e = [Event new];
    e.readyState = kEventStateClosed;
    e.error = error ?: [NSError errorWithDomain:@""
                                  code:e.readyState
                              userInfo:@{ NSLocalizedDescriptionKey: @"Connection with the event source was closed." }];

    [self _dispatchEvent:e type:ReadyStateEvent];
    [self _dispatchEvent:e type:ErrorEvent];

    if (self.retryWhenConnectError) {
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_retryInterval * NSEC_PER_SEC));
        dispatch_after(popTime, connectionQueue, ^(void){
            [self _open];
        });
    }else {
        [self close];
    }
}

- (void)_open {
    wasClosed = NO;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.eventURL
                                                           cachePolicy:NSURLRequestReloadIgnoringCacheData
                                                       timeoutInterval:self.timeoutInterval];
    if (self.lastEventID) {
        [request setValue:self.lastEventID forHTTPHeaderField:@"Last-Event-ID"];
    }

    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
                                                          delegate:self
                                                     delegateQueue:[NSOperationQueue currentQueue]];

    self.eventSourceSession = session;
    self.eventSourceTask = [session dataTaskWithRequest:request];
    [self.eventSourceTask resume];

    Event *e = [Event new];
    e.readyState = kEventStateConnecting;

    [self _dispatchEvent:e type:ReadyStateEvent];

    if (![NSThread isMainThread]) {
        CFRunLoopRun();
    }
}

- (void)_openByTask:(NSURLSessionDataTask *)task {
    wasClosed = NO;

    self.eventSourceTask = task;
    [self.eventSourceTask resume];

    Event *e = [Event new];
    e.readyState = kEventStateConnecting;

    [self _dispatchEvent:e type:ReadyStateEvent];

    if (![NSThread isMainThread]) {
        CFRunLoopRun();
    }
}

- (void)_dispatchEvent:(Event *)event type:(NSString * const)type {
    NSArray *errorHandlers = self.listeners[type];
    for (EventSourceEventHandler handler in errorHandlers) {
        dispatch_async(connectionQueue, ^{
            if ([type isEqualToString:ErrorEvent] && ![NSThread isMainThread]) {
                CFRunLoopStop(CFRunLoopGetCurrent());
            }
            handler(event);
        });
    }
}

- (void)_dispatchEvent:(Event *)event {
    if (event.eventType != nil) {
        [self _dispatchEvent:event type:event.eventType];
    }
}

@end

// ---------------------------------------------------------------------------------------------------------------------

@implementation Event

- (NSString *)description {
    NSString *state = nil;
    switch (self.readyState) {
        case kEventStateConnecting:
            state = @"CONNECTING";
            break;
        case kEventStateOpen:
            state = @"OPEN";
            break;
        case kEventStateClosed:
            state = @"CLOSED";
            break;
    }
    
    return [NSString stringWithFormat:@"<%@: readyState: %@, id: %@; type: %@; data: %@>",
            [self class],
            state,
            self.eventId,
            self.eventType,
            self.data];
}

@end

NSString *const MessageEvent = @"message";
NSString *const ErrorEvent = @"error";
NSString *const OpenEvent = @"open";
NSString *const ReadyStateEvent = @"readyState";
