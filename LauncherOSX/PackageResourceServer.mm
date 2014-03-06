//
//  PackageResourceServer.m
//  SDKLauncher-iOS
//
//  Created by Shane Meyer on 2/28/13.
// Modified by Daniel Weck
//  Copyright (c) 2013 The Readium Foundation. All rights reserved.
//


#ifdef USE_SIMPLE_HTTP_SERVER
#import "AQHTTPServer.h"
#elif defined(USE_MONGOOSE_HTTP_SERVER)
#include "mongoose.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#ifdef PARSE_MULTI_HTTP_RANGES
#import "DDRange.h"
#import "DDNumber.h"
#else
#include <inttypes.h>
#endif
#else
#import "AsyncSocket.h"
#endif

#import "PackageResourceServer.h"
#import "PackageResourceCache.h"
#import "LOXPackage.h"
#import "RDPackageResource.h"


#ifdef USE_SIMPLE_HTTP_SERVER

static LOXPackage * m_LOXHTTPConnection_package;

//@synchronized(self) {
//
//}

////from STACK to HEAP
//void (^ myBlock)(void) = ^ {
//    // your block code is here.
//};
//[IRQ addObject:[[myBlock copy] autorelease]];

//@autoreleasepool {
//while ( !done )
//{
//[[NSRunLoop currentRunLoop] runMode: @"MyRunLoopMode" beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];
//}
//}

static dispatch_semaphore_t m_byteStreamResourceLock = NULL;

#define LOCKED(block) do {\
        dispatch_semaphore_wait(m_byteStreamResourceLock, DISPATCH_TIME_FOREVER);\
        @try {\
            block();\
        } @finally {\
            dispatch_semaphore_signal(m_byteStreamResourceLock);\
        }\
    } while (0);


//[NSThread isMainThread]  ------  dispatch_get_current_queue() == dispatch_get_main_queue()
#define MAINQ(block) if ([NSThread isMainThread]) {\
NSLog(@"MAINQ - main thread");\
block();\
} else {\
NSLog(@"MAINQ - other thread");\
dispatch_sync(dispatch_get_main_queue(), block);\
}

//
//dispatch_sync(self.queue, ^{});
//
//dispatch_async(dispatch_get_main_queue(), ^{
//
//});

@implementation LOXHTTPResponseOperation {
    LOXPackage * m_package;
    RDPackageResource * m_resource;
}

//dispatch_semaphore_t    _lock;
//@synthesize lock=_lock;


//- (id) init
//{
//    self = [super init];
//    if ( self == nil )
//        return ( nil );
//
//    // create a critical section lock
//    //_lock = dispatch_semaphore_create(1);
//
//    m_package = nil;
//    m_resource = nil;
//
//    return ( self );
//}

- (void)initialiseData:(LOXPackage *)package resource:(RDPackageResource *)resource
{
    if (m_package != nil)
    {
        [m_package release];
        m_package = nil;
    }
    m_package = package;
    [m_package retain];

    if (m_resource != nil)
    {
        [m_resource release];
        m_resource = nil;
    }
    m_resource = resource;
    [m_resource retain];

    if (DEBUGLOG)
    {
        NSLog(@"LOXHTTPResponseOperation: %@", m_resource.relativePath);
        NSLog(@"LOXHTTPResponseOperation: %ld", m_resource.bytesCount);
        NSLog(@"LOXHTTPResponseOperation: %@", self);
    }

    // critical section
    //_lock = dispatch_semaphore_create(1);
}

- (void)dealloc {
    if (DEBUGLOG)
    {
        NSLog(@"DEALLOC LOXHTTPResponseOperation");
        NSLog(@"DEALLOC LOXHTTPResponseOperation: %@", m_resource.relativePath);
        NSLog(@"DEALLOC LOXHTTPResponseOperation: %@", self);
    }
//
//#if DISPATCH_USES_ARC == 0
//    if ( _lock != NULL )
//    {
//        dispatch_release(_lock);
//        _lock = NULL;
//    }
//#endif
    if (m_package != nil)
    {
        [m_package release];
    }

    if (m_resource != nil)
    {
        [m_resource release];
    }

    [super dealloc];
}

- (NSUInteger) statusCodeForItemAtPath: (NSString *) rootRelativePath
{
    NSString * method = CFBridgingRelease(CFHTTPMessageCopyRequestMethod(_request));

    if (m_resource == nil)
    {
        return ( 404 );
    }
    else if (method != nil && [method caseInsensitiveCompare: @"DELETE"] == NSOrderedSame )
    {
        // Not Permitted
        return ( 403 );
    }
    else if ( _ranges != nil )
    {
        return ( 206 );
    }

    return ( 200 );
}

- (UInt64) sizeOfItemAtPath: (NSString *) rootRelativePath
{
    return m_resource.bytesCount;
}

- (NSString *) etagForItemAtPath: (NSString *) path
{
    return nil;
}

- (NSInputStream *) inputStreamForItemAtPath: (NSString *) rootRelativePath
{
    return nil;
}

- (id<AQRandomAccessFile>) randomAccessFileForItemAtPath: (NSString *) rootRelativePath
{
    //return [self autorelease];
    return self;
}

-(UInt64)length
{
    return m_resource.bytesCount;
}

- (NSData *) readDataFromByteRange: (DDRange) range
{
    if (m_resource == nil)
    {
        NSLog(@"NOT READY?!");
        return [NSData data];
    }

    if (DEBUGMIN)
    {
        NSLog(@"[%ld ... %ld] (%ld / %ld)", range.location, range.location+range.length-1, range.length, m_resource.bytesCount);
    }

    if (range.length == 0 || m_resource.bytesCount == 0)
    {
        NSLog(@"WTF?!");
        return [NSData data];
    }

    __block NSData * result = nil;

    if (DEBUGLOG)
    {
        NSLog(@"LOCK readDataFromByteRange: %@", self);
    }

    LOCKED(^{

                if (m_skipCache)
                {
                    result = [m_resource createChunkByReadingRange:NSRangeFromDDRange(range) package:m_package];
                }
                else
                {
                    result = [[PackageResourceCache shared] dataAtRelativePath: m_resource.relativePath range:NSRangeFromDDRange(range) resource:m_resource];
                }
        });

    if (DEBUGLOG)
    {
        NSLog(@"un-LOCK readDataFromByteRange: %@", self);
    }

    //result = [NSData data];
    //[result autorelease];

    return result;
}

@end

@implementation LOXHTTPConnection

//- (id) init
//{
//    self = [super init];
//    if ( self == nil )
//        return ( nil );
//
//    return ( self );
//}

- (void)dealloc {
    if (DEBUGLOG)
    {
        NSLog(@"DEALLOC LOXHTTPConnection");
        NSLog(@"DEALLOC LOXHTTPConnection: %@", self);
    }
    [super dealloc];
}

- (BOOL) supportsPipelinedRequests
{
    return YES;
}

- (AQHTTPResponseOperation *) responseOperationForRequest: (CFHTTPMessageRef) request
{
    NSURL * url = (NSURL *)CFBridgingRelease(CFHTTPMessageCopyRequestURL(request));
    if (url == nil)
    {
        return [super responseOperationForRequest: request];
    }

    if (DEBUGLOG)
    {
        NSLog(@"responseOperationForRequest: %@", url);
    }

    NSString * scheme = [url scheme];
    if (scheme == nil || [scheme caseInsensitiveCompare: @"fake"] == NSOrderedSame)
    {
        return [super responseOperationForRequest: request];
    }

    NSString * path = [url path];
    if (path == nil)
    {
        return [super responseOperationForRequest: request];
    }


    NSString * relPath = [m_LOXHTTPConnection_package resourceRelativePath: path];
    if (relPath == nil)
    {
        return [super responseOperationForRequest: request];
    }

    __block RDPackageResource *resource =nil;

    LOCKED(^{
        resource = [m_LOXHTTPConnection_package resourceAtRelativePath:relPath];
    });

    if (resource == nil)
    {
        return [super responseOperationForRequest: request];
    }

    __block int contentLength = 0;

    if (m_skipCache)
    {
        contentLength = resource.bytesCount;
    }
    else
    {
        LOCKED(^{
            contentLength = [[PackageResourceCache shared] contentLengthAtRelativePath: resource.relativePath resource:resource];

            if (contentLength == 0) {
                [[PackageResourceCache shared] addResource:resource];

                contentLength = [[PackageResourceCache shared] contentLengthAtRelativePath: resource.relativePath resource:resource];
            }
        });
    }

    if (contentLength == 0)
    {
        NSLog(@"WHAT? contentLength 0");
        return [super responseOperationForRequest: request];
    }

    NSString * rangeHeader = CFBridgingRelease(CFHTTPMessageCopyHeaderFieldValue(request, CFSTR("Range")));
    NSArray * ranges = nil;
    if ( rangeHeader != nil )
    {
        ranges = [self parseRangeRequest: rangeHeader withContentLength: contentLength];
    }

    LOXHTTPResponseOperation * op = [[LOXHTTPResponseOperation alloc] initWithRequest: request socket: self.socket ranges: ranges forConnection: self];
    [op initialiseData:m_LOXHTTPConnection_package resource:resource];

    [resource release]; //was alloc'ed

#if USING_MRR
//#error "THIS SHOULD FAIL AT COMPILE TIME"
    [op autorelease];
#endif
    return ( op );
}
@end
#elif defined(USE_MONGOOSE_HTTP_SERVER)

#ifdef PARSE_MULTI_HTTP_RANGES

static NSArray * parseRangeRequest(NSString * rangeHeader, UInt64 contentLength)
{
//	HTTPLogTrace();

// Examples of byte-ranges-specifier values (assuming an entity-body of length 10000):
//
// - The first 500 bytes (byte offsets 0-499, inclusive):  bytes=0-499
//
// - The second 500 bytes (byte offsets 500-999, inclusive): bytes=500-999
//
// - The final 500 bytes (byte offsets 9500-9999, inclusive): bytes=-500
//
// - Or bytes=9500-
//
// - The first and last bytes only (bytes 0 and 9999):  bytes=0-0,-1
//
// - Several legal but not canonical specifications of the second 500 bytes (byte offsets 500-999, inclusive):
// bytes=500-600,601-999
// bytes=500-700,601-999
//

NSRange eqsignRange = [rangeHeader rangeOfString:@"="];

if(eqsignRange.location == NSNotFound) return nil;

NSUInteger tIndex = eqsignRange.location;
NSUInteger fIndex = eqsignRange.location + eqsignRange.length;

NSMutableString *rangeType  = [[rangeHeader substringToIndex:tIndex] mutableCopy];
NSMutableString *rangeValue = [[rangeHeader substringFromIndex:fIndex] mutableCopy];
#if USING_MRR
    [rangeType autorelease];
    [rangeValue autorelease];
#endif

CFStringTrimWhitespace((__bridge CFMutableStringRef)rangeType);
CFStringTrimWhitespace((__bridge CFMutableStringRef)rangeValue);

if([rangeType caseInsensitiveCompare:@"bytes"] != NSOrderedSame) return nil;

NSArray *rangeComponents = [rangeValue componentsSeparatedByString:@","];

if([rangeComponents count] == 0) return nil;

NSMutableArray * ranges = [[NSMutableArray alloc] initWithCapacity:[rangeComponents count]];
#if USING_MRR
    [ranges autorelease];
#endif

// Note: We store all range values in the form of DDRange structs, wrapped in NSValue objects.
// Since DDRange consists of UInt64 values, the range extends up to 16 exabytes.

NSUInteger i;
for (i = 0; i < [rangeComponents count]; i++)
{
NSString *rangeComponent = [rangeComponents objectAtIndex:i];

NSRange dashRange = [rangeComponent rangeOfString:@"-"];

if (dashRange.location == NSNotFound)
{
// We're dealing with an individual byte number

UInt64 byteIndex;
if(![NSNumber parseString:rangeComponent intoUInt64:&byteIndex]) return nil;

if(byteIndex >= contentLength) return nil;

[ranges addObject:[NSValue valueWithDDRange:DDMakeRange(byteIndex, 1)]];
}
else
{
// We're dealing with a range of bytes

tIndex = dashRange.location;
fIndex = dashRange.location + dashRange.length;

NSString *r1str = [rangeComponent substringToIndex:tIndex];
NSString *r2str = [rangeComponent substringFromIndex:fIndex];

UInt64 r1, r2;

BOOL hasR1 = [NSNumber parseString:r1str intoUInt64:&r1];
BOOL hasR2 = [NSNumber parseString:r2str intoUInt64:&r2];

if (!hasR1)
{
// We're dealing with a "-[#]" range
//
// r2 is the number of ending bytes to include in the range

if(!hasR2) return nil;
if(r2 > contentLength) return nil;

UInt64 startIndex = contentLength - r2;

[ranges addObject:[NSValue valueWithDDRange:DDMakeRange(startIndex, r2)]];
}
else if (!hasR2)
{
// We're dealing with a "[#]-" range
//
// r1 is the starting index of the range, which goes all the way to the end

if(r1 >= contentLength) return nil;

[ranges addObject:[NSValue valueWithDDRange:DDMakeRange(r1, contentLength - r1)]];
}
else
{
// We're dealing with a normal "[#]-[#]" range
//
// Note: The range is inclusive. So 0-1 has a length of 2 bytes.

if(r1 > r2) return nil;
if(r2 >= contentLength) return nil;

[ranges addObject:[NSValue valueWithDDRange:DDMakeRange(r1, r2 - r1 + 1)]];
}
}
}

if([ranges count] == 0) return nil;

// NB: no sorting or combining-- that's being done later

return [NSArray arrayWithArray: ranges];
}

#else

static int parse_range_header(const char *header, int64_t *a, int64_t *b) {
    return sscanf(header, "bytes=%" PRId64 "-%" PRId64, a, b);
}

#endif


static void gmt_time_string(char *buf, size_t buf_len, time_t *t) {
    strftime(buf, buf_len, "%a, %d %b %Y %H:%M:%S GMT", gmtime(t));
}


static dispatch_semaphore_t m_byteStreamResourceLock = NULL;

#define LOCKED(block) do {\
        dispatch_semaphore_wait(m_byteStreamResourceLock, DISPATCH_TIME_FOREVER);\
        @try {\
            block();\
        } @finally {\
            dispatch_semaphore_signal(m_byteStreamResourceLock);\
        }\
    } while (0);



struct server_info_t {
    struct mg_server * server;
    PackageResourceServer * packServer;
};


struct connection_param_t {
    RDPackageResource *resource;
};

static int mg_ev_handler(struct mg_connection *conn, enum mg_event ev)
{
//    enum mg_event {
//        MG_POLL = 100,  // Callback return value is ignored
//        MG_CONNECT,     // If callback returns MG_FALSE, connect fails
//        MG_AUTH,        // If callback returns MG_FALSE, authentication fails
//        MG_REQUEST,     // If callback returns MG_FALSE, Mongoose continues with req
//        MG_REPLY,       // If callback returns MG_FALSE, Mongoose closes connection
//        MG_CLOSE,       // Connection is closed
//        MG_HTTP_ERROR   // If callback returns MG_FALSE, Mongoose continues with err
//    };
@autoreleasepool {
    struct server_info_t* serverInfo = (struct server_info_t*)conn->server_param;


    if (ev == MG_CONNECT)
    {
        printf("MG_CONNECT\n");
        return serverInfo->packServer.doPollServer ? MG_TRUE : MG_FALSE;
    }
    else if (ev == MG_AUTH)
    {
        printf("MG_AUTH\n");
        return serverInfo->packServer.doPollServer ? MG_TRUE : MG_FALSE;
    }
    else if (ev == MG_REPLY)
    {
        printf("MG_REPLY\n");
        return serverInfo->packServer.doPollServer ? MG_TRUE : MG_FALSE;
    }
    else if (ev == MG_POLL)
    {
        printf("MG_POLL\n");
        return MG_TRUE;
    }
    else if (ev == MG_REQUEST)
    {
        if (!serverInfo->packServer.doPollServer) return MG_TRUE;

        LOXPackage * package = serverInfo->packServer.package;
        NSString * pack_id = [package packageUUID];

        printf("======================\n");
        if (conn->content_len > 0)
        {
            //char * content = new char[conn->content_len];
            char content[conn->content_len+1];
            strncpy(content, conn->content, conn->content_len);
            content[conn->content_len] = '\0';
            printf("mg_connection->content %s\n", content);
            //delete content;
        }
        printf("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n");

        printf("mg_connection->connection_param %d\n", conn->connection_param);

        printf("mg_connection->request_method %s\n", conn->request_method);

        printf("mg_connection->status_code %d\n", conn->status_code);

        printf("mg_connection->local_ip %s\n", conn->local_ip);
        printf("mg_connection->local_ip %d\n", conn->local_port);

        printf("mg_connection->http_version %s\n", conn->http_version);
        printf("mg_connection->query_string %s\n", conn->query_string);

        for (int i = 0; i < conn->num_headers; i++)
        {
            printf("******\n");
            printf("mg_connection->http_headers[%d]->name  ||| %s\n", i, conn->http_headers[i].name);
            printf("mg_connection->http_headers[%d]->value ||| %s\n", i, conn->http_headers[i].value);
            printf("******\n");
        }

        printf("mg_connection->uri %s\n", conn->uri);

        const char * packId = [pack_id UTF8String];
        printf("mg_connection->server_param (LOXPackage.packageUUID) %s\n", packId);
        printf("----------------------\n");


        if (strcmp(conn->request_method, "GET") != 0)
        {
            printf("NOT GET REQUEST??\n");
            return MG_TRUE;
        }

        size_t uriLen = strlen(conn->uri);
        size_t packIdLen = strlen(packId);
        if (uriLen < packIdLen || strncmp(conn->uri+1, packId, packIdLen) != 0)
        {
            printf("BAD PACKAGE UUI?!\n");
            return MG_TRUE;
        }

        bool excludeLeadingSlash = 1; // 0 TRUE, 1 FALSE
        size_t len = uriLen - packIdLen - 1 - excludeLeadingSlash;
        //char * path = new char[len];
        char path[len+1];
        strncpy(path, conn->uri + packIdLen + 1 + excludeLeadingSlash, len);
        path[len] = '\0';
        printf("REL PATH (from conn->uri) %s\n", path);
        NSString * relPath = [NSString stringWithUTF8String: path];
        //delete path;

        __block RDPackageResource *resource =nil;

        if (conn->connection_param == NULL)
        {
            printf("NEW (conn->connection_param)\n");

            LOCKED(^{
                resource = [package resourceAtRelativePath:relPath];
            });

            if (resource == nil)
            {
                printf("BAD RDPackageResource path?!\n");
                return MG_TRUE;
            }

            struct connection_param_t * connection_param;
            connection_param = (struct connection_param_t *) malloc(sizeof(*connection_param));
            conn->connection_param = connection_param;
            connection_param->resource = resource;
        }
        else
        {
            printf("OLD (conn->connection_param)\n");

            resource = ((struct connection_param_t *)conn->connection_param)->resource;

            if (resource == nil)
            {
                printf("ERROR !!! ((struct connection_param_t *)conn->connection_param)->resource\n");

                free(conn->connection_param);
                conn->connection_param = NULL;

                return MG_TRUE;
            }
        }



        printf("RDPackageResource path: %s\n", [[resource relativePath] UTF8String]);

        int contentLength = resource.bytesCount;

        if (contentLength == 0)
        {
            NSLog(@"WHAT? contentLength 0");
            return MG_TRUE;
        }

        printf("RDPackageResource bytes: %d\n", contentLength);

        const char * mime = mg_get_mime_type(conn->uri, "text/plain");
        printf("RDPackageResource mime: %s\n", mime);

        const char * connex = mg_get_header(conn, "Connection");
        bool keepAlive = false;
        if (strcmp(connex, "keep-alive") == 0) keepAlive = true;

        const char * hdr = mg_get_header(conn, "Range");

        time_t curtime = time(NULL);
        char date[64];
        gmt_time_string(date, sizeof(date), &curtime);

#ifdef PARSE_MULTI_HTTP_RANGES
        NSArray * ranges = nil;
        if (hdr != NULL)
        {
            conn->status_code = 206;
            ranges = parseRangeRequest([NSString stringWithUTF8String:hdr], contentLength);
        }
#else
        int n;
        int64_t r1 = 0;
        int64_t r2 = 0;
        if (hdr != NULL
            && (n = parse_range_header(hdr, &r1, &r2)) > 0
            && r1 >= 0 && r2 >= 0)
        {
            conn->status_code = 206;

            int64_t rangeLength = n == 2 ? (r2 > contentLength ? contentLength : r2) - r1 + 1: contentLength - r1;

            printf("********* RANGE: %d - %d (%d) / %d\n", r1, r2, rangeLength, contentLength);

            mg_printf(conn, "%s%s%s%s%s%d%s%d%s%d%s%d%s",
                    "HTTP/1.1 206 Partial Content\r\n"
                    "Date: ",
                    date,
                    "\r\n"
                    "Server: ReadiumPackageResourceServer\r\n"
                    "Accept-Ranges: bytes\r\n"
                    "Connection: ",
                    (keepAlive ? "keep-alive" : "close"),
                    "\r\n"
                    "Content-Length: ",
                    rangeLength,
                    "\r\n"
                    "Content-Range: bytes ",
                    r1, "-", r2, "/", contentLength,
                    "\r\n"
                    "\r\n"
            );
            printf("%s%s%s%s%s%d%s%d%s%d%s%d%s",
                    "HTTP/1.1 206 Partial Content\r\n"
                            "Date: ",
                    date,
                    "\r\n"
                            "Server: ReadiumPackageResourceServer\r\n"
                            "Accept-Ranges: bytes\r\n"
                            "Connection: ",
                    (keepAlive ? "keep-alive" : "close"),
                    "\r\n"
                            "Content-Length: ",
                    rangeLength,
                    "\r\n"
                            "Content-Range: bytes ",
                    r1, "-", r2, "/", contentLength,
                    "\r\n"
                            "\r\n"
            );

            NSRange range = {.location = (uint)r1, .length = (uint)rangeLength};

            NSData *data = [resource createChunkByReadingRange:range package:package];
            if (data != nil)
            {
                int nBytes = [data length];
                if (nBytes > 0)
                {
                    printf("++++++ BYTES: %d\n", nBytes);

                    mg_write(conn, [data bytes], nBytes);
                    mg_write(conn, "\r\n", 2);
                }

                //[data release];
            }
        }
        else
        {
            printf("????? PackageResource FULL!\n");

            conn->status_code = 200;

            mg_printf(conn, "%s%s%d%s",
                    "HTTP/1.1 200 OK\r\n"
                            "Date: ",
                    date,
                    "\r\n"
                            "Server: ReadiumPackageResourceServer\r\n"
                            "Accept-Ranges: bytes\r\n"
                            "Connection: close\r\n"
                            "Content-Length: ",
                    contentLength,
                    "\r\n"
                            "\r\n"
            );
            printf("%s%s%s%d%s",
                    "HTTP/1.1 200 OK\r\n"
                            "Date: ",
                    date,
                    "\r\n"
                            "Server: ReadiumPackageResourceServer\r\n"
                            "Accept-Ranges: bytes\r\n"
                            "Connection: close\r\n"
                            "Content-Length: ",
                    contentLength,
                    "\r\n"
                            "\r\n"
            );



            NSData *data = [resource readAllDataChunks];
            if (data != nil)
            {
                int nBytes = [data length];
                if (nBytes > 0)
                {
                    mg_write(conn, [data bytes], nBytes);
                    mg_write(conn, "\r\n", 2);
                }

                //[data release];
            }
        }
#endif

        return MG_FALSE;
    }
    else if (ev == MG_CLOSE)
    {
        printf("{{{{{{{{{{{{{{{{{{{{{{{{{ CLOSE\n");

        if (conn->connection_param != NULL)
        {
            printf("free(conn->connection_param)\n");

            [((struct connection_param_t *)conn->connection_param)->resource release];

            free(conn->connection_param);
            conn->connection_param = NULL;
        }

        return MG_FALSE;
    }
}
    return MG_FALSE;
}
//
//void pthread_cleanup(void * arg)
//{
//    printf("pthread_cleanup mg_destroy_server\n");
//    mg_destroy_server((struct mg_server **)&arg);
//}

static void *mg_serve(void *serverInformation)
{
    printf("NSThread.isMultiThreaded %d\n", NSThread.isMultiThreaded);


//    pthread_setcancelstate(PTHREAD_CANCEL_ENABLE, NULL);
//    pthread_setcanceltype(PTHREAD_CANCEL_DEFERRED, NULL);

    struct server_info_t* serverInfo = (struct server_info_t*)serverInformation;

    unsigned int num_active_connections = 0;

    pthread_mutex_t * mutex = serverInfo->packServer.mutex;

    pthread_mutex_lock(mutex);

    // uses pthread_self()
    //pthread_cleanup_push(&pthread_cleanup, (struct mg_server *)server); // MACRO: opens lexical scope {
    printf("THREAD (before loop) \n");

    while (serverInfo->packServer.doPollServer || num_active_connections > 0)
    {
        //printf("THREAD %d (poll) %p\n", num_active_connections, serverInfo->server);

        num_active_connections = mg_poll_server(serverInfo->server, 200); // ms

        //pthread_testcancel();
    }

    printf("THREAD (after loop) %d\n", num_active_connections);
    //pthread_cleanup_pop(1); // MACRO: closes lexical scope }

    mg_destroy_server(&serverInfo->server);
    serverInfo->server = NULL;

    //[serverInfo->packServer release];
    serverInfo->packServer = nil;

    printf("free(serverInfo);\n");

    free(serverInfo);
    serverInfo = NULL;

    printf("pthread_mutex_unlock\n");

    pthread_mutex_unlock(mutex);

    printf("pthread_exit\n");

    //pthread_exit((void*)'z');
    //pthread_exit(NULL);
    return NULL;
}

#else
const static int m_socketTimeout = 60;

@interface PackageRequest : NSObject {
	@private int m_byteCountWrittenSoFar;
	@private NSDictionary *m_headers;
	@private NSRange m_range;
	@private RDPackageResource *m_resource;
	@private AsyncSocket *m_socket;
}

@property (nonatomic, assign) int byteCountWrittenSoFar;
@property (nonatomic, retain) NSDictionary *headers;
@property (nonatomic, assign) NSRange range;
@property (nonatomic, retain) RDPackageResource *resource;
@property (nonatomic, retain) AsyncSocket *socket;

@end

@implementation PackageRequest

@synthesize byteCountWrittenSoFar = m_byteCountWrittenSoFar;
@synthesize headers = m_headers;
@synthesize range = m_range;
@synthesize resource = m_resource;
@synthesize socket = m_socket;

- (void)dealloc {
	[m_headers release];
	[m_resource release];
	[m_socket release];
	[super dealloc];
}

@end

#endif



@interface PackageResourceServer()


#ifdef USE_SIMPLE_HTTP_SERVER
//noop
#elif defined(USE_MONGOOSE_HTTP_SERVER)
//noop
#else
@property (nonatomic, readonly) NSString *dateString;

- (void)writeNextResponseChunkForRequest:(PackageRequest *)request;
#endif

@end


@implementation PackageResourceServer {
    LOXPackage * m_package;
}
//
//- (id) init
//{
//    self = [super init];
//    if ( self == nil )
//        return ( nil );
//
//    m_package = nil;
//
//    return ( self );
//}

- (int) serverPort
{
    return m_kSDKLauncherPackageResourceServerPort;
}

#if defined(USE_MONGOOSE_HTTP_SERVER)

- (LOXPackage *) package
{
    return m_package;
}

- (int) doPollServer
{
    return m_doPollServer;
}

- (pthread_mutex_t*) mutex
{
    return &m_mutex;
}

#endif

- (void)dealloc {

    if (DEBUGLOG)
    {
        NSLog(@"DEALLOC Pack Res Server ");
    }

#ifdef USE_SIMPLE_HTTP_SERVER

#if DISPATCH_USES_ARC == 0
    if ( m_byteStreamResourceLock != NULL )
    {
        //dispatch_semaphore_signal(m_byteStreamResourceLock);
        dispatch_release(m_byteStreamResourceLock);
        m_byteStreamResourceLock = NULL;
    }
#endif

    if ([m_server isListening])
    {
        [m_server stop];
    }
    [m_server release];
#elif defined(USE_MONGOOSE_HTTP_SERVER)

    printf("mongoose dealloc\n");

#if DISPATCH_USES_ARC == 0
    if ( m_byteStreamResourceLock != NULL )
    {
        //dispatch_semaphore_signal(m_byteStreamResourceLock);
        dispatch_release(m_byteStreamResourceLock);
        m_byteStreamResourceLock = NULL;
    }
#endif

    if (m_threadId != NULL)
    {
        printf("pthread_cancel join\n");

        //pthread_exit(m_threadId);
        //pthread_kill(m_threadId, 0);

        //pthread_cancel(m_threadId);

        m_doPollServer = false;

        printf("pthread_mutex_lock...\n");
        pthread_mutex_lock(&m_mutex);

//        char *c;
//        int ret = pthread_join(m_threadId, (void**)&c);
//        //ret == EINVAL ==> PTHREAD_CREATE_DETACHED :(

        m_threadId = NULL;

        printf("pthread_cancel join DONE\n");
    }

    m_server = NULL;

    printf("pthread_mutex_destroy\n");
    pthread_mutex_destroy(&m_mutex);

// done when thread gets cleaned-up
//    if (m_server != NULL)
//    {
//        printf("DESTROY SERVER THREAD (dealloc)\n");
//        mg_destroy_server(&m_server);
//    }

#else
	NSArray *requests = [[NSArray alloc] initWithArray:m_requests];
	for (PackageRequest *request in requests) {
		// Disconnecting causes onSocketDidDisconnect to be called, which removes the request
		// from the array, which is why we iterate a copy of that array.
		[request.socket disconnect];
	}
	[requests release];
	[m_mainSocket release];
    [m_requests release];
#endif

    printf("[m_package release];\n");

	[m_package release];

    printf("[super dealloc];\n");

	[super dealloc];
}

- (id)initWithPackage:(LOXPackage *)package resourcesFromZipStream_NoFileSystemEncryptedCache:(BOOL)resourcesFromZipStream_NoFileSystemEncryptedCache {
	if (package == nil) {
		[self release];
		return nil;
	}

	if (self = [super init]) {

		m_package = [package retain];

        m_skipCache = resourcesFromZipStream_NoFileSystemEncryptedCache;

NSLog(@"Skip encrypted filesystem cache, use direct ZIP byte stream: %d", m_skipCache);

#ifdef USE_SIMPLE_HTTP_SERVER


        // create a critical section lock
        m_byteStreamResourceLock = dispatch_semaphore_create(1);


//        NSString * port = [NSString stringWithFormat:@"%d", kSDKLauncherPackageResourceServerPort];
//        NSString * address = [@"localhost:" stringByAppendingString:port];
        NSString * address = @"localhost";
        NSURL * url = [NSURL fileURLWithPath: [@"file:///" stringByAppendingString:[m_package packageUUID]]];

        m_server = [[AQHTTPServer alloc] initWithAddress: address root: url]; //retained

//        [LOXHTTPConnection setPackage: m_package];
//        if (m_LOXHTTPConnection_package != nil)
//        {
//            [m_LOXHTTPConnection_package release];
//        }
        m_LOXHTTPConnection_package = m_package;
//        [m_LOXHTTPConnection_package retain];

        [m_server setConnectionClass:[LOXHTTPConnection class]];

        NSError * error = nil;
        if ( [m_server start: &error] == NO )
        {
            NSLog(@"Error starting server: %@", error);
            [self release];
            return nil;
        }
        m_kSDKLauncherPackageResourceServerPort = [m_server serverPort];

        if (DEBUGMIN)
        {
            NSLog(@"HTTP");
            NSLog(@"%@", [m_server serverAddress]);
        }
#elif defined(USE_MONGOOSE_HTTP_SERVER)

        // create a critical section lock
        m_byteStreamResourceLock = dispatch_semaphore_create(1);

        pthread_mutex_init(&m_mutex, NULL);

        //struct server_info_t * serverInfo = new (struct server_info_t)();
        struct server_info_t * serverInfo;
        serverInfo = (struct server_info_t *) malloc(sizeof(*serverInfo));

        serverInfo->packServer = self; // [self retain];  NO! (otherwise dealloc never called)

        //mg_ev_handler ===> endpoint_type == EP_USER
        m_server = mg_create_server((void *)serverInfo, mg_ev_handler);

        serverInfo->server = m_server;

//        m_kSDKLauncherPackageResourceServerPort = 8080;
//        NSString * port = [NSString stringWithFormat:@"%d", m_kSDKLauncherPackageResourceServerPort];
//        mg_set_option(server, "listening_port", [port UTF8String]);

        mg_set_option(m_server, "listening_port", "0");
        const char * portStr = mg_get_option(m_server, "listening_port");
        m_kSDKLauncherPackageResourceServerPort = strtol(portStr, NULL, 10);

        printf("Resource server port: %d\n", m_kSDKLauncherPackageResourceServerPort);

        m_doPollServer = true;


        m_threadId = (pthread_t)mg_start_thread(mg_serve, serverInfo);

#else
#error "HTTP ???"
		m_requests = [[NSMutableArray alloc] init];
		m_mainSocket = [[AsyncSocket alloc] initWithDelegate:self];
		[m_mainSocket setRunLoopModes:@[ NSRunLoopCommonModes ]];

		NSError *error = nil;

        m_kSDKLauncherPackageResourceServerPort = 8080;
		if (![m_mainSocket acceptOnPort:m_kSDKLauncherPackageResourceServerPort error:&error]) {
			NSLog(@"The main socket could not be created! %@", error);
			[self release];
			return nil;
		}
#endif
	}

	return self;
}


#ifdef USE_SIMPLE_HTTP_SERVER
//noop
#elif defined(USE_MONGOOSE_HTTP_SERVER)
//noop
#else
- (NSString *)dateString {
	NSDateFormatter *fmt = [[[NSDateFormatter alloc] init] autorelease];
	[fmt setDateFormat:@"EEE, dd MMM yyyy HH:mm:ss"];
	[fmt setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
	return [[fmt stringFromDate:[NSDate date]] stringByAppendingString:@" GMT"];
}

- (void)onSocket:(AsyncSocket *)sock didAcceptNewSocket:(AsyncSocket *)newSocket {

    if (DEBUGLOG)
    {
        NSLog(@"SOCK %@", newSocket);
    }

	PackageRequest *request = [[[PackageRequest alloc] init] autorelease];
	request.socket = newSocket;
	[m_requests addObject:request];
}


- (void)onSocket:(AsyncSocket *)sock didConnectToHost:(NSString *)host port:(UInt16)port {
	[sock readDataWithTimeout:m_socketTimeout tag:0];
}


- (void)onSocket:(AsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
	if (data == nil || data.length == 0) {
		NSLog(@"The HTTP request data is missing!");
		[sock disconnect];
		return;
	}

	if (data.length >= 8192) {
		NSLog(@"The HTTP request data is unexpectedly large!");
		[sock disconnect];
		return;
	}

	NSString *s = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
		autorelease];

	if (s == nil || s.length == 0) {
		NSLog(@"Could not read the HTTP request as a string!");
		[sock disconnect];
		return;
	}

	// Parse the HTTP method, path, and headers.

	NSMutableDictionary *headers = [NSMutableDictionary dictionary];
	PackageRequest *request = nil;
	BOOL firstLine = YES;

	for (NSString *line in [s componentsSeparatedByString:@"\r\n"]) {
		if (firstLine) {
			firstLine = NO;
			NSArray *tokens = [line componentsSeparatedByString:@" "];

			if (tokens.count != 3) {
				NSLog(@"The first line of the HTTP request does not have 3 tokens!");
				[sock disconnect];
				return;
			}

			NSString *method = [tokens objectAtIndex:0];

			if (![method isEqualToString:@"GET"]) {
				NSLog(@"The HTTP method is not GET!");
				[sock disconnect];
				return;
			}

			NSString *path = [tokens objectAtIndex:1];

			if (path.length == 0) {
				NSLog(@"The HTTP request path is missing!");
				[sock disconnect];
				return;
			}

			NSRange range = [path rangeOfString:@"/"];

			if (range.location != 0) {
				NSLog(@"The HTTP request path doesn't begin with a forward slash!");
				[sock disconnect];
				return;
			}

			range = [path rangeOfString:@"/" options:0 range:NSMakeRange(1, path.length - 1)];

			if (range.location == NSNotFound) {
				NSLog(@"The HTTP request path is incomplete!");
				[sock disconnect];
				return;
			}

			NSString *packageUUID = [path substringWithRange:NSMakeRange(1, range.location - 1)];

			if (![packageUUID isEqualToString:m_package.packageUUID]) {
				NSLog(@"The HTTP request has the wrong package UUID!");
				[sock disconnect];
				return;
			}

			path = [path substringFromIndex:NSMaxRange(range)];
			RDPackageResource *resource = [m_package resourceAtRelativePath:path];

			if (resource == nil) {
				NSLog(@"The package resource is missing!");
				[sock disconnect];
				return;
			}

			for (PackageRequest *currRequest in m_requests) {
				if (currRequest.socket == sock) {
					currRequest.headers = headers;
					currRequest.resource = resource;
					request = currRequest;
					break;
				}
			}

			if (request == nil) {
				NSLog(@"Could not find our request!");
				[sock disconnect];
				return;
			}
		}
		else {
			NSRange range = [line rangeOfString:@":"];

			if (range.location != NSNotFound) {
				NSString *key = [line substringToIndex:range.location];
				key = [key stringByTrimmingCharactersInSet:
					[NSCharacterSet whitespaceAndNewlineCharacterSet]];

				NSString *val = [line substringFromIndex:range.location + 1];
				val = [val stringByTrimmingCharactersInSet:
					[NSCharacterSet whitespaceAndNewlineCharacterSet]];

				[headers setObject:val forKey:key.lowercaseString];
			}
		}
	}

	int contentLength = 0;

    if (m_skipCache)
    {
        contentLength = request.resource.bytesCount;
    }
    else
    {
        contentLength = [[PackageResourceCache shared] contentLengthAtRelativePath:
		request.resource.relativePath resource:request.resource];

        if (contentLength == 0) {
            [[PackageResourceCache shared] addResource:request.resource];

            contentLength = [[PackageResourceCache shared] contentLengthAtRelativePath:
                request.resource.relativePath resource:request.resource];
        }
    }

	NSString *commonResponseHeaders = [NSString stringWithFormat:
		@"Date: %@\r\n"
		@"Server: PackageResourceServer\r\n"
		@"Accept-Ranges: bytes\r\n"
		@"Connection: close\r\n",
		self.dateString];

	// Handle requests that specify a 'Range' header, which iOS makes use of.  See:
	// http://developer.apple.com/library/ios/#documentation/AppleApplications/Reference/SafariWebContent/CreatingVideoforSafarioniPhone/CreatingVideoforSafarioniPhone.html#//apple_ref/doc/uid/TP40006514-SW6

	NSString *rangeToken = [headers objectForKey:@"range"];

	if (rangeToken != nil) {
		rangeToken = rangeToken.lowercaseString;

		if (![rangeToken hasPrefix:@"bytes="]) {
			NSLog(@"The requests's range doesn't begin with 'bytes='!");
			[sock disconnect];
			return;
		}

		rangeToken = [rangeToken substringFromIndex:6];

		NSArray *rangeValues = [rangeToken componentsSeparatedByString:@"-"];

		if (rangeValues == nil || rangeValues.count != 2) {
			NSLog(@"The requests's range doesn't have two values!");
			[sock disconnect];
			return;
		}

		NSString *s0 = [rangeValues objectAtIndex:0];
		NSString *s1 = [rangeValues objectAtIndex:1];

		s0 = [s0 stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		s1 = [s1 stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];

		if (s0.length == 0 || s1.length == 0) {
			NSLog(@"The requests's range has a blank value!");
			[sock disconnect];
			return;
		}

		int p0 = s0.intValue;
		int p1 = s1.intValue;

        int length = p1 + 1 - p0;
        request.range = NSMakeRange(p0, length);

        if (DEBUGLOG)
        {
            NSLog(@"[%@] [%d , %d] (%d) / %d", request.resource.relativePath, p0, p1, request.range.length, contentLength);
        }

		NSMutableString *ms = [NSMutableString stringWithCapacity:512];
		[ms appendString:@"HTTP/1.1 206 Partial Content\r\n"];
		[ms appendString:commonResponseHeaders];
		[ms appendFormat:@"Content-Length: %d\r\n", request.range.length];
		[ms appendFormat:@"Content-Range: bytes %d-%d/%d\r\n", p0, p1, contentLength];
		[ms appendString:@"\r\n"];

		[sock writeData:[ms dataUsingEncoding:NSUTF8StringEncoding] withTimeout:m_socketTimeout tag:0];
	}
	else {
        if (DEBUGLOG)
        {
            NSLog(@"Entire HTTP file");
        }

		request.range = NSMakeRange(0, contentLength);

		NSMutableString *ms = [NSMutableString stringWithCapacity:512];
		[ms appendString:@"HTTP/1.1 200 OK\r\n"];
		[ms appendString:commonResponseHeaders];
		[ms appendFormat:@"Content-Length: %d\r\n", request.range.length];
		[ms appendString:@"\r\n"];

		[sock writeData:[ms dataUsingEncoding:NSUTF8StringEncoding] withTimeout:m_socketTimeout tag:0];
	}

	[self writeNextResponseChunkForRequest:request];
}


- (void)onSocket:(AsyncSocket *)sock didWriteDataWithTag:(long)tag {
	PackageRequest *request = nil;

	for (PackageRequest *currRequest in m_requests) {
		if (currRequest.socket == sock) {
			request = currRequest;
			break;
		}
	}

	if (request == nil) {
		NSLog(@"Could not find our request!");
		[sock disconnect];
	}
	else {
		[self writeNextResponseChunkForRequest:request];
	}
}


- (void)onSocket:(AsyncSocket *)sock willDisconnectWithError:(NSError *)err {
    if (DEBUGLOG)
    {
        NSLog(@"SOCK-ERR %@", sock);
    }
	NSLog(@"The socket disconnected with an error! %@", err);
}


- (void)onSocketDidDisconnect:(AsyncSocket *)sock {

    if (DEBUGLOG)
    {
        NSLog(@"~SOCK %@", sock);
    }
	for (PackageRequest *request in m_requests) {
		if (request.socket == sock) {
			[[sock retain] autorelease];
			[m_requests removeObject:request];
			return;
		}
	}
}


- (void)writeNextResponseChunkForRequest:(PackageRequest *)request {
	int p0 = request.range.location + request.byteCountWrittenSoFar;
	int p1 = MIN((int)NSMaxRange(request.range), p0 + 1024 * 1024);

	if (p0 == p1) {
		// Done.
		return;
	}

	BOOL lastChunk = (p1 == NSMaxRange(request.range));

    auto range = NSMakeRange(p0, p1 - p0);

    if (DEBUGLOG)
    {
        NSLog(@">> [%@] [%d , %d] (%d) ... %d", request.resource.relativePath, p0, p1, range.length, request.byteCountWrittenSoFar);
    }

    NSData *data = nil;
    if (m_skipCache)
    {
        data = [request.resource createChunkByReadingRange:range package:m_package];
    }
    else
    {
        data = [[PackageResourceCache shared] dataAtRelativePath:
                request.resource.relativePath range:range resource:request.resource];
    }

	if (data == nil || data.length != p1 - p0) {
		NSLog(@"The data is empty or has the wrong length!");
		[request.socket disconnect];
	}
	else {
		request.byteCountWrittenSoFar += (p1 - p0);
		[request.socket writeData:data withTimeout:m_socketTimeout tag:0];

		if (lastChunk) {
			[request.socket disconnectAfterWriting];
		}
	}
}
#endif


@end
