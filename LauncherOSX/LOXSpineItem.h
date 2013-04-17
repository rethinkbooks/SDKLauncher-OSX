//  Created by Boris Schneiderman.
//  Copyright (c) 2012-2013 The Readium Foundation.
//
//  The Readium SDK is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//



#import <Foundation/Foundation.h>
#import "spine.h"


namespace ePub3 {
    class SpineItem;
}

@interface LOXSpineItem : NSObject {

@private
    const ePub3::SpineItem * _sdkSpineItem;
    NSString* _idref;

    NSString* _packageStorrageId;
}

@property(nonatomic, readonly) NSString *idref;
@property(nonatomic, readonly) NSString *packageStorageId;
@property(nonatomic, readonly) NSString *href;

- (const ePub3::SpineItem *) sdkSpineItem;

- (id)initWithStorageId:(NSString *)storageId forSdkSpineItem:(ePub3::SpineItem const *)sdkSpineItem;


@end