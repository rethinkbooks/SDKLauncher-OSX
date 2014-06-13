//
//  LOXWebViewController.m
//  LauncherOSX
//
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

#import <WebKit/WebKit.h>
#import "LOXWebViewController.h"
#import "LOXPackage.h"
#import "LOXSpineItem.h"
#import "LOXCurrentPagesInfo.h"
#import "LOXBookmark.h"
#import "LOXPreferences.h"
#import "LOXAppDelegate.h"
#import "LOXCSSStyle.h"
#import "LOXOpenPageInfo.h"
#import "LOXUtil.h"
#import "LOXMediaOverlayController.h"
#import "PackageResourceServer.h"
#import "RDPackageResource.h"
#import <ePub3/utilities/byte_stream.h>
#import <CoreGraphics/CoreGraphics.h>

@interface LOXWebViewController ()

-(void)onPageChanged:(NSNotification*) notification;

- (NSString *)loadHtmlTemplate;

- (void)updateUI;
@end


@implementation LOXWebViewController {

    LOXPackage *_package;
    NSString* _baseUrlPath;
}


- (NSURLRequest *)webView:(WebView *)sender
                 resource:(id)identifier
          willSendRequest:(NSURLRequest *)request
         redirectResponse:(NSURLResponse *)redirectResponse
           fromDataSource:(WebDataSource *)dataSource
{
    if (request.URL == nil)
    {
        return request;
    }

    NSString *scheme = request.URL.scheme;

    if (scheme == nil)
    {
        return request;
    }

    NSString *path = request.URL.path;
    if (path == nil)
    {
        return request;
    }

    if ([scheme caseInsensitiveCompare: @"file"] != NSOrderedSame)
    {
        return request;
    }

    if (_package == nil)
    {
        return request;
    }


    if ([path hasPrefix:@"/"]) {
        path = [path substringFromIndex:1];
    }

    NSString * str = [[NSString stringWithFormat:@"http://127.0.0.1:%d/%@/%@",
                                                 [m_resourceServer serverPort],
                                                 _package.packageUUID, path] stringByAddingPercentEscapesUsingEncoding : NSUTF8StringEncoding];
    NSURL *url = [NSURL URLWithString:str];

    NSMutableURLRequest *newRequest = [request mutableCopy];
    [newRequest setURL: url];

    return newRequest;
}

- (LOXPackage *) loxPackage
{
    return _package;
}

- (void)awakeFromNib
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];

    [nc addObserver:self
                                             selector:@selector(onPageChanged:)
                                                 name:LOXPageChangedEvent
                                               object:nil];

    NSString* html = [self loadHtmlTemplate];

    NSURL *baseUrl = [NSURL fileURLWithPath:_baseUrlPath];

    [[_webView mainFrame] loadHTMLString:html baseURL:baseUrl];
}

-(void)onPageChanged:(NSNotification*) notification
{
    [self updateUI];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(savePageImage)
                                               object:nil];
    [self performSelector:@selector(savePageImage)
               withObject:nil
               afterDelay:1.0];
}

- (IBAction)onLeftPageClick:(id)sender
{
    WebScriptObject* script = [_webView windowScriptObject];
    [script evaluateWebScript:@"ReadiumSDK.reader.openPageLeft()"];
}


- (IBAction)onRightPageClick:(id)sender
{
    WebScriptObject* script = [_webView windowScriptObject];
    [script evaluateWebScript:@"ReadiumSDK.reader.openPageRight()"];
}

-(NSString*) getCurrentPageCfi
{
    WebScriptObject* script = [_webView windowScriptObject];
    NSString* cfi = [script evaluateWebScript: @"ReadiumSDK.reader.getFirstVisibleElementCfi()"];
    return cfi;
}


- (NSString*) loadHtmlTemplate
{
    NSString* path = [[NSBundle mainBundle] pathForResource:@"reader" ofType:@"html" inDirectory:@"Scripts"];

    _baseUrlPath = [path stringByDeletingLastPathComponent];

    NSString* htmlTemplate = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];

    if (!htmlTemplate){
        @throw [NSException exceptionWithName:@"Resource Exception" reason:@"Resourse reader.html not found" userInfo:nil];
    }

    return htmlTemplate;
}

-(void)openPackage:(LOXPackage *)package onPage:(LOXBookmark*) bookmark
{
    _package = package;

    m_resourceServer = nil;
    m_resourceServer = [[PackageResourceServer alloc] initWithPackage:package];

    NSMutableDictionary *dict = [NSMutableDictionary dictionary];

    [dict setObject:[_package toDictionary] forKey:@"package"];

    if(bookmark) {
        NSDictionary *locationDict = [[NSDictionary alloc] initWithObjectsAndKeys:bookmark.idref, @"idref", bookmark.contentCFI, @"elementCfi", nil];
        [dict setObject:locationDict forKey:@"openPageRequest"];
    }

    NSString *json = [LOXUtil toJson:dict];
    //NSLog(@"%@", json);

    NSString* callString = [NSString stringWithFormat:@"ReadiumSDK.reader.openBook(%@)", json];

    [_webView stringByEvaluatingJavaScriptFromString:callString];
}

- (void)clear
{
    WebScriptObject* script = [_webView windowScriptObject];
    [script evaluateWebScript: @"ReadiumSDK.reader.reset()"];
}


//this allows JavaScript to call the -logJavaScriptString: method
+ (BOOL)isSelectorExcludedFromWebScript:(SEL)sel
{
    if(        sel == @selector(onOpenPage:)
            || sel == @selector(onReaderInitialized)
            || sel == @selector(onSettingsApplied)
            || sel == @selector(onMediaOverlayStatusChanged:)
            || sel == @selector(onMediaOverlayTTSSpeak:)
            || sel == @selector(onMediaOverlayTTSStop)
            ){

        return NO;
    }

    return YES;
}

//this returns a nice name for the method in the JavaScript environment
+(NSString*)webScriptNameForSelector:(SEL)sel
{
    if(sel == @selector(onOpenPage:)) {
        return @"onOpenPage";
    }
    else if(sel == @selector(onReaderInitialized)) {
        return @"onReaderInitialized";
    }
    else if(sel == @selector(onSettingsApplied)) {
        return @"onSettingsApplied";
    }
    else if(sel == @selector(onMediaOverlayStatusChanged:)) {
        return @"onMediaOverlayStatusChanged";
    }
    else if(sel == @selector(onMediaOverlayTTSSpeak:)) {
        return @"onMediaOverlayTTSSpeak";
    }
    else if(sel == @selector(onMediaOverlayTTSStop)) {
        return @"onMediaOverlayTTSStop";
    }

    return nil;
}


//this is called as soon as the script environment is ready in the webview
- (void)webView:(WebView *)sender didClearWindowObject:(WebScriptObject *)windowScriptObject forFrame:(WebFrame *)frame
{
    //add the controller to the script environment
    //the "Cocoa" object will now be available to JavaScript
    [windowScriptObject setValue:self forKey:@"LauncherUI"];
}

- (void)onOpenPage:(NSString*) currentPaginationInfo
{

    NSData* data = [currentPaginationInfo dataUsingEncoding:NSUTF8StringEncoding];

    NSError *e = nil;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData: data options: NSJSONReadingMutableContainers error: &e];

    if (e) {
        NSLog(@"Error parsing JSON: %@", e);
        return;
    }

    [self.currentPagesInfo fromDictionary:dict];
    [[NSNotificationCenter defaultCenter] postNotificationName:LOXPageChangedEvent object:self];

}

- (void)onMediaOverlayTTSStop
{
    [[NSNotificationCenter defaultCenter] postNotificationName:LOXMediaOverlayTTSStopEvent object:self userInfo:nil];
}

- (void)onMediaOverlayTTSSpeak:(NSString*) tts
{
    NSData* data = [tts dataUsingEncoding:NSUTF8StringEncoding];

    NSError *e = nil;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData: data options: NSJSONReadingMutableContainers error: &e];

    if (e) {
        NSLog(@"Error parsing JSON: %@", e);
        return;
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:LOXMediaOverlayTTSSpeakEvent object:self userInfo:dict];
}

- (void)onMediaOverlayStatusChanged:(NSString*) status
{
    NSData* data = [status dataUsingEncoding:NSUTF8StringEncoding];

    NSError *e = nil;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData: data options: NSJSONReadingMutableContainers error: &e];

    if (e) {
        NSLog(@"Error parsing JSON: %@", e);
        return;
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:LOXMediaOverlayStatusChangedEvent object:self userInfo:dict];
}

-(bool)isMediaOverlayAvailable
{
    NSString* callString = @"ReadiumSDK.reader.isMediaOverlayAvailable()";

    NSString *result = [_webView stringByEvaluatingJavaScriptFromString:callString];

    return [result boolValue];
}

-(void)setStyles:(NSArray *)styles
{
    NSMutableArray *arr = [NSMutableArray array];

    for(LOXCSSStyle *style in styles) {
        [arr addObject:[style toDictionary]];
    }

    NSString* jsonDecl = [LOXUtil toJson: arr];
    //NSLog(@"%@", jsonDecl);

    NSString* callString = [NSString stringWithFormat:@"ReadiumSDK.reader.setStyles(%@)", jsonDecl];
    [_webView stringByEvaluatingJavaScriptFromString:callString];
}

- (void)onReaderInitialized
{
    [self.appDelegate onReaderInitialized];
}


-(void)updateSettings:(LOXPreferences *)preferences
{
    [[self.appDelegate mediaOverlayController] updateSettings: preferences];

    NSString *jsonString = [LOXUtil toJson:[preferences toDictionary]];
    //NSLog(@"%@", jsonString);

    NSString* callString = [NSString stringWithFormat:@"ReadiumSDK.reader.updateSettings(%@)", jsonString];
    [_webView stringByEvaluatingJavaScriptFromString:callString];
}


- (void)controlTextDidChange:(NSNotification *)notification {
    NSTextField *textField = [notification object];
    NSLog(@"controlTextDidChange: stringValue == %@", [textField stringValue]);
}


- (void)updateUI
{
    [self.leftPageButton setEnabled:[self.currentPagesInfo canGoLeft]];
    [self.rightPageButton setEnabled:[self.currentPagesInfo canGoRight]];
}


- (void)savePageImage
{
    NSError *error;

    NSMutableString *script = [[NSMutableString alloc] init];
    [script appendString:@"var innerBody = document.getElementById('epubContentIframe').contentDocument.body;\n"];
    [script appendString:@"var innerBodyRect = innerBody.getBoundingClientRect();\n"];
    [script appendString:@"var result = {left: innerBodyRect.left, top: innerBodyRect.top, right: innerBodyRect.right, bottom: innerBodyRect.bottom};\n"];
    [script appendString:@"JSON.stringify(result);"];
    NSString *resultJSON = [_webView stringByEvaluatingJavaScriptFromString:script];
    NSDictionary *result = [NSJSONSerialization JSONObjectWithData:[resultJSON dataUsingEncoding:NSUTF8StringEncoding]
                                                           options:0
                                                             error:&error];

    NSRect bounds = _webView.bounds;
    bounds.origin.y = bounds.size.height - [result[@"bottom"] floatValue];
    bounds.size.width = [result[@"right"] floatValue];
    bounds.size.height = [result[@"bottom"] floatValue];
    NSData *pdfData = [_webView dataWithPDFInsideRect:bounds];

    LOXOpenPageInfo *pageInfo = [[[self currentPagesInfo] openPages] lastObject];
    NSString *filePath = [NSString stringWithFormat:@"/Users/adexter/Desktop/page%d.pdf", [pageInfo spineItemIndex]];
    if (![pdfData writeToFile:filePath options:0 error:&error]) {
        NSLog(@"Failed to write file: %@", error);
    }

    if ([self.currentPagesInfo canGoRight]) {
        [self onRightPageClick:nil];
    } else {
        NSArray *srcPages = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/Users/adexter/Desktop" error:NULL];
        srcPages = [srcPages filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id obj, NSDictionary *env) {
            NSString *path = obj;
            return [path hasPrefix:@"page"] && [path hasSuffix:@".pdf"];
        }]];

        CGRect mediaBox = CGRectMake(0.0f, 0.0f, bounds.size.width, bounds.size.height);
        CGContextRef pdfContext = CGPDFContextCreateWithURL((CFURLRef) [NSURL URLWithString:@"file:///Users/adexter/Desktop/book.pdf"],
                                                     &mediaBox,
                                                     NULL);
        for (NSString *pagePath in srcPages) {
            CGPDFDocumentRef pageDoc = CGPDFDocumentCreateWithURL((CFURLRef) [NSURL URLWithString:[NSString stringWithFormat:@"file:///Users/adexter/Desktop/%@", pagePath]]);
            CGContextBeginPage(pdfContext, &mediaBox);
            CGContextDrawPDFPage(pdfContext, CGPDFDocumentGetPage(pageDoc, 1));
            CGContextEndPage(pdfContext);
            CGPDFDocumentRelease(pageDoc);
        }
        CGPDFContextClose(pdfContext);
    }
}


//- (int)getPageForElementId:(NSString *)elementId
//{
//    WebScriptObject* script = [_webView windowScriptObject];
//    NSString *callString = [NSString stringWithFormat:@"ReadiumSDK.reader.getPageForElementId(\"%@\")", elementId];
//    NSString* ret = [script evaluateWebScript:callString];
//
//    if ([ret isMemberOfClass:[WebUndefined class]]){
//        NSLog(@"element id j//    }
//
//    return [ret intValue];
//}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)spineView:(LOXSpineViewController *)spineViewController selectionChangedTo:(LOXSpineItem *)spineItem
{
    [self openSpineItem:spineItem.idref pageIndex:0];
}

- (void)openSpineItem:idref elementCfi:(NSString *)cfi
{
    WebScriptObject* script = [_webView windowScriptObject];
    [script evaluateWebScript:[NSString stringWithFormat:@"ReadiumSDK.reader.openSpineItemElementCfi(\"%@\", \"%@\")", idref, cfi]];
}

- (void)openSpineItem:(NSString*)idref pageIndex:(int)pageIx
{
    WebScriptObject* script = [_webView windowScriptObject];
    [script evaluateWebScript:[NSString stringWithFormat:@"ReadiumSDK.reader.openSpineItemPage(\"%@\", %d)", idref, pageIx]];
}

- (void)openPage:(int)pageIndex
{
    WebScriptObject* script = [_webView windowScriptObject];
    [script evaluateWebScript:[NSString stringWithFormat:@"ReadiumSDK.reader.openPageIndex(%d)", pageIndex]];
}

- (void)openContentUrl:(NSString *)contentRef fromSourceFileUrl:(NSString*) sourceRef
{
    WebScriptObject* script = [_webView windowScriptObject];

    NSString* sourceRefParam = sourceRef ? sourceRef : @"";

    [script evaluateWebScript:[NSString stringWithFormat:@"ReadiumSDK.reader.openContentUrl(\"%@\", \"%@\")", contentRef, sourceRefParam]];
}

-(LOXBookmark*) createBookmark
{

    WebScriptObject* script = [_webView windowScriptObject];
    NSString *callString = @"ReadiumSDK.reader.bookmarkCurrentPage()";
    NSString * bookmarkData = [script evaluateWebScript:callString];

    NSData* data = [bookmarkData dataUsingEncoding:NSUTF8StringEncoding];

    NSError *e = nil;
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData: data options: NSJSONReadingMutableContainers error: &e];

    if (!dict) {
        NSLog(@"Error parsing JSON: %@", e);
        return nil;
    }

    LOXBookmark *bookmark = [[LOXBookmark alloc] init];

    bookmark.idref = dict[@"idref"];
    bookmark.contentCFI = dict[@"contentCFI"];

    return bookmark;
}


-(void)onSettingsApplied
{
    NSLog(@"Settings has been applied to the reader");
}

- (void)resetStyles
{
    WebScriptObject* script = [_webView windowScriptObject];
    [script evaluateWebScript: @"ReadiumSDK.reader.clearStyles()"];
}


- (void)mediaOverlaysOpenContentUrl:(NSString *)contentRef fromSourceFileUrl:(NSString*) sourceRef forward:(double) offset
{
    WebScriptObject* script = [_webView windowScriptObject];

    NSString* sourceRefParam = sourceRef ? sourceRef : @"";

    [script evaluateWebScript:[NSString stringWithFormat:@"ReadiumSDK.reader.mediaOverlaysOpenContentUrl(\"%@\", \"%@\", %f)", contentRef, sourceRefParam, offset]];
}

- (void)toggleMediaOverlay
{
    WebScriptObject* script = [_webView windowScriptObject];
    [script evaluateWebScript: @"ReadiumSDK.reader.toggleMediaOverlay()"];
}

- (void)nextMediaOverlay
{
    WebScriptObject* script = [_webView windowScriptObject];
    [script evaluateWebScript: @"ReadiumSDK.reader.nextMediaOverlay()"];
}
- (void)previousMediaOverlay
{
    WebScriptObject* script = [_webView windowScriptObject];
    [script evaluateWebScript: @"ReadiumSDK.reader.previousMediaOverlay()"];
}
- (void)escapeMediaOverlay
{
    WebScriptObject* script = [_webView windowScriptObject];
    [script evaluateWebScript: @"ReadiumSDK.reader.escapeMediaOverlay()"];
}
- (void)ttsEndedMediaOverlay
{
    WebScriptObject* script = [_webView windowScriptObject];
    [script evaluateWebScript: @"ReadiumSDK.reader.ttsEndedMediaOverlay()"];
}

@end
