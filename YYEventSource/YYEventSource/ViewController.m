//
//  ViewController.m
//  YYEventSource
//
//  Created by xiaotian on 2021/2/23.
//

#import "ViewController.h"
#import "EventSource.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    [self connect];
}

- (void)connect {
    NSString *url = @"http://127.0.0.1:8844/stream";
    EventSource *eventSource = [EventSource eventSourceWithURL:[NSURL URLWithString:url]];

    [eventSource onMessage:^(Event *e) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"%@", e);
        });
    }];
    
    [eventSource onError:^(Event *event) {
        NSLog(@"error:%@", event.error);
    }];
}

@end
