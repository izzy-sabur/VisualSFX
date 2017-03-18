//
//  Interface.m
//  VisualSFX
//
//  Created by eightball on 10/17/16.
//  Copyright © 2016 Violin. All rights reserved.
//

#import "Interface.h"

@interface Interface ()

@property (weak) IBOutlet NSWindow *window;
@end


CGContextRef CreateARGBBitmapContext (CGImageRef inImage)
{
    CGContextRef    context = NULL;
    CGColorSpaceRef colorSpace;
    void *          bitmapData;
    int             bitmapByteCount;
    int             bitmapBytesPerRow;
    
    // Get image width, height. We'll use the entire image.
    size_t pixelsWide = CGImageGetWidth(inImage);
    size_t pixelsHigh = CGImageGetHeight(inImage);
    
    // Declare the number of bytes per row. Each pixel in the bitmap in this
    // example is represented by 4 bytes; 8 bits each of red, green, blue, and
    // alpha.
    bitmapBytesPerRow   = (pixelsWide * 4);
    bitmapByteCount     = (bitmapBytesPerRow * pixelsHigh);
    
    // Use the generic RGB color space.
    colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
    if (colorSpace == NULL)
    {
        fprintf(stderr, "Error allocating color space\n");
        return NULL;
    }
    
    // Allocate memory for image data. This is the destination in memory
    // where any drawing to the bitmap context will be rendered.
    bitmapData = malloc( bitmapByteCount );
    if (bitmapData == NULL)
    {
        fprintf (stderr, "Memory not allocated!");
        CGColorSpaceRelease( colorSpace );
        return NULL;
    }
    
    // Create the bitmap context. We want pre-multiplied ARGB, 8-bits
    // per component. Regardless of what the source image format is
    // (CMYK, Grayscale, and so on) it will be converted over to the format
    // specified here by CGBitmapContextCreate.
    context = CGBitmapContextCreate (bitmapData,
                                     pixelsWide,
                                     pixelsHigh,
                                     8,      // bits per component
                                     bitmapBytesPerRow,
                                     colorSpace,
                                     kCGImageAlphaPremultipliedFirst);
    if (context == NULL)
    {
        free (bitmapData);
        fprintf (stderr, "Context not created!");
    }
    
    // Make sure and release colorspace before returning
    CGColorSpaceRelease( colorSpace );
    
    return context;
}

void* ManipulateImagePixelData(CGContextRef cgctx, CGImageRef inImage)
{
    if (cgctx == NULL)
    {
        // error creating context
        return NULL;
    }
    
    // Get image width, height. We'll use the entire image.
    size_t w = CGImageGetWidth(inImage);
    size_t h = CGImageGetHeight(inImage);
    CGRect rect = {{0,0},{w,h}};
    
    // Draw the image to the bitmap context. Once we draw, the memory
    // allocated for the context for rendering will then contain the
    // raw image data in the specified color space.
    CGContextDrawImage(cgctx, rect, inImage);
    
    // Now we can get a pointer to the image data associated with the bitmap
    // context.
    void *data = CGBitmapContextGetData (cgctx);
    if (data != NULL)
    {
        return data;
    }
    return NULL;
    
    
}

void FreeImagePixelData(void* pixelData, CGContextRef cgctx)
{
    // When finished, release the context
    CGContextRelease(cgctx);
    // Free image data memory for the context
    if (pixelData)
    {
        free(pixelData);
    }
}

@implementation Interface

- (void)awakeFromNib
{
    mStream = [[SynthEngine alloc] init];
    unitPrecision = 10;
    volumeUnitPrecision = 50;
    mDurSlider.continuous = true;
    [self sliderChangeValue:0];
    [self playbackSliderChangeValue:0];
    [self realtimeSliderChangeValue:0];
}

- (void)loadNewImageFile
{
    if(mImagePath == NULL)
        return;
    
    if(mCurrImage != NULL)
        CFRelease(mCurrImage);
    
    if(mCurrContext != NULL)
        FreeImagePixelData(mCurrImageData, mCurrContext);
    
    NSURL *url = mImagePath;
    mCurrImage = NULL;
    CGImageSourceRef  myImageSource;
    CFDictionaryRef   myOptions = NULL;
    CFStringRef       myKeys[2];
    CFTypeRef         myValues[2];
    
    // Set up options if you want them. The options here are for
    // caching the image in a decoded form and for using floating-point
    // values if the image format supports them.
    myKeys[0] = kCGImageSourceShouldCache;
    myValues[0] = (CFTypeRef)kCFBooleanTrue;
    myKeys[1] = kCGImageSourceShouldAllowFloat;
    myValues[1] = (CFTypeRef)kCFBooleanTrue;
    // Create the dictionary
    myOptions = CFDictionaryCreate(NULL, (const void **) myKeys,
                                   (const void **) myValues, 2,
                                   &kCFTypeDictionaryKeyCallBacks,
                                   & kCFTypeDictionaryValueCallBacks);
    // Create an image source from the URL.
    myImageSource = CGImageSourceCreateWithURL((CFURLRef)url, myOptions);
    CFRelease(myOptions);
    // Make sure the image source exists before continuing
    if (myImageSource == NULL)
    {
        fprintf(stderr, "Image source is NULL.");
        return;
    }
    // Create an image from the first item in the image source.
    mCurrImage = CGImageSourceCreateImageAtIndex(myImageSource,
                                              0,
                                              NULL);
    
    CFRelease(myImageSource);
    // Make sure the image exists before continuing
    if (mCurrImage == NULL)
    {
        fprintf(stderr, "Image not created from image source.");
        return;
    }
    
    mCurrContext = CreateARGBBitmapContext(mCurrImage);
    mCurrImageData = ManipulateImagePixelData(mCurrContext, mCurrImage);
}

- (IBAction)loadFileFromPath:(id)sender
{
    NSOpenPanel *openPanel = [[NSOpenPanel alloc] init];
    
    [openPanel setCanChooseFiles:true];
    [openPanel setCanChooseDirectories:false];
    [openPanel setAllowsMultipleSelection:false];
    
    if ( [openPanel runModal] == NSModalResponseOK )
    {
        // Get an array containing the full filenames of all
        // files and directories selected.
        NSArray* files = [openPanel URLs];
        
        // Loop through all the files and process them.
        for(int i = 0; i < [files count]; i++ )
        {
            NSURL* fileName = [files objectAtIndex:i];
            
            mImagePath = fileName;
        }
        
        [self loadNewImageFile];
    }
    
    mImageButton.image = [[NSImage alloc] initByReferencingURL:mImagePath];
}

- (IBAction)playSoundFromImage:(id)sender
{
    [mStream createAudioDataFromImageData:mCurrImageData imageRef:mCurrImage];
}

- (IBAction)writeFileFromImage:(id)sender
{
    [mStream writeAudioFileFromAudioData:mImagePath];
}

- (IBAction)sliderChangeValue:(id)sender
{
    float newDur = mDurSlider.floatValue / unitPrecision;
    mStream->mSoundDuration = newDur;
    NSMutableString* newString = [[NSMutableString alloc] init];
    NSString *str = [NSString stringWithFormat:@"%.2f", newDur];
    [newString appendString:str];
    [newString appendString:@"s"];
    mDurText.stringValue =  newString;
}

- (IBAction)playbackSliderChangeValue:(id)sender
{
    float newVol = mPlaybackSlider.floatValue / volumeUnitPrecision;
    mStream->mPlaybackVol = newVol;
}

- (IBAction)realtimeSliderChangeValue:(id)sender
{
    float newVol = mRealtimeSlider.floatValue / volumeUnitPrecision;
    mStream->mRealtimeVol = newVol;
}

- (IBAction)dropdownChangeValue:(id)sender
{
    switch(mWaveformMenu.selectedTag)
    {
        case 0:
            mStream->mGrainType = SineWave;
            break;
        case 1:
            mStream->mGrainType = SawtoothWave;
            break;
        case 2:
            mStream->mGrainType = SquareWave;
            break;
        case 3:
            mStream->mGrainType = TriangleWave;
            break;
    }
}

- (IBAction)togglePlayback:(id)sender
{
    if (mPlaybackCheckbox.state == NSOnState)
        mStream->mPlaybackOn = false;
    else
        mStream->mPlaybackOn = true;
}
@end




