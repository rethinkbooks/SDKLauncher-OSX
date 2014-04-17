//
//  LOXePubSdkApi.m
//  LauncherOSX
//
//  Created by Boris Schneiderman.
//  Copyright (c) 2014 Readium Foundation and/or its licensees. All rights reserved.
//  
//  Redistribution and use in source and binary forms, with or without modification, 
//  are permitted provided that the following conditions are met:
//  1. Redistributions of source code must retain the above copyright notice, this 
//  list of conditions and the following disclaimer.
//  2. Redistributions in binary form must reproduce the above copyright notice, 
//  this list of conditions and the following disclaimer in the documentation and/or 
//  other materials provided with the distribution.
//  3. Neither the name of the organization nor the names of its contributors may be 
//  used to endorse or promote products derived from this software without specific 
//  prior written permission.
//  
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
//  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED 
//  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. 
//  IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, 
//  INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
//  BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, 
//  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF 
//  LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE 
//  OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED 
//  OF THE POSSIBILITY OF SUCH DAMAGE.

#import "LOXePubSdkApi.h"

#import <ePub3/container.h>
#import <ePub3/nav_table.h>
#include <ePub3/initialization.h>

#import "LOXSpineItem.h"
#import "LOXPackage.h"



@interface LOXePubSdkApi ()

- (void)cleanup;

- (void)readPackages;

@end

@implementation LOXePubSdkApi {
    NSMutableArray *_packages;

    ePub3::ContainerPtr _container;

    LOXPackage* _currentPackage;
}


+(void)initialize
{
    ePub3::InitializeSdk();
    ePub3::PopulateFilterManager();
}

- (id)init
{
    self = [super init];
    
    if(self){

        _packages = [NSMutableArray array];
    }

    return self;
}

- (LOXPackage *)openFile:(NSString *)file
{
    [self cleanup];

     _container = ePub3::Container::OpenContainer([file UTF8String]);

    [self readPackages];

    if([_packages count] > 0) {
        return [_packages objectAtIndex:0];
    }

    return nil;
}

- (void)readPackages
{
    auto packages = _container->Packages();

    for (auto package = packages.begin(); package != packages.end(); ++package) {

        [_packages addObject:[[LOXPackage alloc] initWithSdkPackage:*package]];
    }
}


- (void)dealloc
{
    [self cleanup];
}

- (void)cleanup
{
    [_packages removeAllObjects];
    _currentPackage = nil;
}






@end
