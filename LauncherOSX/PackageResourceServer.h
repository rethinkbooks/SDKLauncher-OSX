//
//  PackageResourceServer.h
//  SDKLauncher-iOS
//
//  Created by Shane Meyer on 2/28/13.
// Modified by Daniel Weck
//  Copyright (c) 2013 The Readium Foundation. All rights reserved.
//

#import <Foundation/Foundation.h>

@class LOXPackage;
@class RDPackageResource;

static BOOL m_skipCache = true;


#ifdef USE_SIMPLE_HTTP_SERVER

#import "AQHTTPConnection.h"
#import "AQHTTPResponseOperation.h"

@class AQHTTPServer;

@interface LOXHTTPResponseOperation : AQHTTPResponseOperation<AQRandomAccessFile>
{
}
//@property (nonatomic, readonly) dispatch_semaphore_t lock;
- (void)initialiseData:(LOXPackage *)package resource:(RDPackageResource *)resource;
@end

@interface LOXHTTPConnection : AQHTTPConnection
{

}
@end
#elif defined(USE_MONGOOSE_HTTP_SERVER)
#import "mongoose.h"
#else
#error "AsyncSocket??"
@class AsyncSocket;
#endif

@interface PackageResourceServer : NSObject {

@private int m_kSDKLauncherPackageResourceServerPort;

#ifdef USE_SIMPLE_HTTP_SERVER
    AQHTTPServer * m_server;
#elif defined(USE_MONGOOSE_HTTP_SERVER)
    pthread_t m_threadId;
    struct mg_server * m_server;
    @private bool m_doPollServer;
    pthread_mutex_t m_mutex; //PTHREAD_MUTEX_INITIALIZER

#else
	@private AsyncSocket *m_mainSocket;
	@private NSMutableArray *m_requests;
#endif
}

- (id)initWithPackage:(LOXPackage *)package resourcesFromZipStream_NoFileSystemEncryptedCache:(BOOL)resourcesFromZipStream_NoFileSystemEncryptedCache;

- (int) serverPort;

#if defined(USE_MONGOOSE_HTTP_SERVER)
- (int) doPollServer;
- (LOXPackage *) package;
- (pthread_mutex_t*) mutex;
#endif

@end
