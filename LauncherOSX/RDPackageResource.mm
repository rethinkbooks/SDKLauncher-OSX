//
//  RDPackageResource.mm
//  SDKLauncher-iOS
//
//  Created by Shane Meyer on 2/28/13.
// Modified by Daniel Weck
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

#import "RDPackageResource.h"
#import "LOXPackage.h"

#import <ePub3/archive.h>
#import <ePub3/utilities/byte_stream.h>

@interface RDPackageResource() {
@private ePub3::ByteStream* m_byteStream;
@private NSString *m_relativePath;


@private std::size_t m_bytesCount;
@private UInt8 m_buffer[kSDKLauncherPackageResourceBufferSize];
//@private NSData *m_data;
}

@end


@implementation RDPackageResource

//@synthesize byteStream = m_byteStream;
@synthesize bytesCount = m_bytesCount;
@synthesize relativePath = m_relativePath;
@synthesize package = m_package;

- (NSData *)data {
    if (m_data == nil) {

        if (m_bytesCount == 0)
        {
            m_data = [NSData data];
        }
        else
        {
            NSMutableData *md = [[NSMutableData alloc] initWithCapacity: m_bytesCount];

            while (YES) {
                std::size_t count = m_byteStream->ReadBytes(m_buffer, sizeof(m_buffer));

                if (count <= 0) {
                    break;
                }

                [md appendBytes:m_buffer length:count];
            }

            m_data = md;
        }
    }

    return m_data;
}


+ (std::size_t)bytesAvailable:(ePub3::ByteStream*)byteStream pack:(LOXPackage *)package path:(NSString *)relPath {
    std::size_t size = byteStream->BytesAvailable();
    if (size == 0)
    {
        NSLog(@"BYTESTREAM zero BytesAvailable!");
    }
    else
    {
        return size;
    }

    //std::unique_ptr<ePub3::ArchiveReader> reader = _sdkPackage->ReaderForRelativePath(s);
    //reader->read(<#(void*)p#>, <#(size_t)len#>)

    std::shared_ptr<ePub3::Archive> archive = [package sdkPackage]->Archive();

    try
    {
        //ZipItemInfo
        ePub3::ArchiveItemInfo info = archive->InfoAtPath([package sdkPackage]->BasePath() + [relPath UTF8String]);
        size = info.UncompressedSize();
    }
    catch (std::exception& e)
    {
        auto msg = e.what();
        NSLog(@"!!! [ArchiveItemInfo] ZIP file not found (corrupted archive?): %@ (%@)", relPath, [NSString stringWithUTF8String:msg]);
    }
    catch (...) {
        throw;
    }

    archive = nullptr;



    std::string s = [relPath UTF8String];
    std::unique_ptr<ePub3::ArchiveReader> reader = [package sdkPackage]->ReaderForRelativePath(s);

    if (reader == nullptr)
    {
        NSLog(@"!!! [ArchiveReader] ZIP file not found (corrupted archive?): %@", relPath);
    }
    else
    {
        UInt8 buffer[kSDKLauncherPackageResourceBufferSize];
        std::size_t total = 0;
        std::size_t count = 0;
        while ((count = reader->read(buffer, sizeof(buffer))) > 0)
        {
            total += count;
        }

        if (total > 0)
        {
            // ByteStream bug??! zip_fread works with ArchiveReader, why not ByteStream?
            NSLog(@"WTF??!");

            if (total != size)
            {
                NSLog(@"Oh dear...");
            }
        }
    }

    reader = nullptr;

    return size;
}

- (NSData *)readDataOfLength:(NSUInteger)length {
    if (length == 0)
    {
        return [NSData data];
    }

    NSMutableData *md = [[NSMutableData alloc] initWithCapacity: length];
    NSUInteger totalRead = 0;

    while (totalRead < length) {
        NSUInteger thisLength = MIN(sizeof(m_buffer), length - totalRead);
        std::size_t count = m_byteStream->ReadBytes(m_buffer, thisLength);
        totalRead += count;
        [md appendBytes:m_buffer length:count];

        if (count != thisLength) {
            NSLog(@"Did not read the expected number of bytes! (%lu %d)", count, thisLength);
            break;
        }
    }

    return md;
}


- (void)setOffset:(UInt64)offset {
    ePub3::SeekableByteStream* seekStream = dynamic_cast<ePub3::SeekableByteStream*>(m_byteStream);
    ePub3::ByteStream::size_type pos = seekStream->Seek(offset, std::ios::beg);

    if (pos != offset) {
        NSLog(@"Setting the byte stream offset failed! pos = %lu, offset = %llu", pos, offset);
    }
}



- (void)dealloc {

    // calls Close() on ByteStream destruction
    if (m_byteStream != nullptr)
    {
        delete m_byteStream;
        m_byteStream = nullptr;
    }
}


- (id)
	initWithByteStream:(ePub3::ByteStream*)byteStream
	relativePath:(NSString *)relativePath
    pack:(LOXPackage *)package
{
	if (byteStream == nil
            || relativePath == nil || relativePath.length == 0) {
		return nil;
	}

	if (self = [super init]) {

        m_package = package;
        m_relativePath = relativePath;

        m_byteStream = byteStream;
        m_bytesCount = [RDPackageResource bytesAvailable:m_byteStream pack:package path:m_relativePath];

        if (m_bytesCount == 0)
        {
            NSLog(@"m_bytesCount == 0 ???? %@", m_relativePath);
        }

	}

	return self;
}


@end
