# YYEventSource

##### Start server on `http://127.0.0.1:8844/stream`.

```js
node sse-server.js
```

##### Open the url in browser.

##### or

##### Request by OC code.

```objc
#import "EventSource.h"
```

connect:

```objc
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
```

You will see the message in console.

PS: Base on [code](https://github.com/neilco/EventSource).