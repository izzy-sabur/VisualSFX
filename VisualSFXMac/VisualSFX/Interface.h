//
//  Interface.h
//  VisualSFX
//
//  Created by eightball on 10/17/16.
//  Copyright © 2016 Violin. All rights reserved.
//

/*!
 @header Interface.h
 
 @brief The interface for the app interface.
 
 @author Izzy Abdus-Sabur
 @copyright  2016 Izzy Abdus-Sabur
 @version    0.1
 */

#import <Cocoa/Cocoa.h>
#include "SynthEngine.h"
@interface Interface : NSObject <NSApplicationDelegate>
{
    IBOutlet NSButton *mLoadImageButton;
    IBOutlet NSButton *mPlayImageButton;
    IBOutlet NSButton *mSaveSoundButton;
    IBOutlet NSButton *mImageButton;
    IBOutlet NSSlider *mDurSlider;
    IBOutlet NSSlider *mPlaybackSlider;
    IBOutlet NSSlider *mRealtimeSlider;
    IBOutlet NSTextField *mDurText;
    IBOutlet NSPopUpButton * mWaveformMenu;
    IBOutlet NSButton *mPlaybackCheckbox;
    
    SynthEngine *mStream;
    float unitPrecision;
    float volumeUnitPrecision;
    NSURL *mImagePath;
    CGImageRef mCurrImage;
    CGContextRef mCurrContext;
    void* mCurrImageData;
}

/*!
 @brief Initialization of the app interface.
 */
- (void)awakeFromNib;

/*!
 @brief Loads a new image file contained at mImagePath. Also loads the data into memory, stored in
        a bitmap context in a 32 bit ARGB format, in mCurrImageData.
 */
- (void)loadNewImageFile;

/*!
 @brief Loads a file from the path when the Load Image button is clicked.
 
 @param sender  The id of the sender button.
 
 @return IBAction  A possible return action to be done.
 */
- (IBAction)loadFileFromPath:(id)sender;

/*!
 @brief Renders and plays a sound effect based on the loaded image. If the sound has already been
        rendered, then it just plays back the rendered sound effect.
 
 @param sender  The id of the sender button.
 
 @return IBAction  A possible return action to be done.
 */
- (IBAction)playSoundFromImage:(id)sender;

/*!
 @brief Writes the rendered sound effect to a file with the same destination and name as the image
        file provided.
 
 @param sender  The id of the sender button.
 
 @return IBAction  A possible return action to be done.
 */
- (IBAction)writeFileFromImage:(id)sender;

/*!
 @brief Changes the mSoundDuration value in the SynthEngine to match the mDurSlider value.
 
 @param sender  The id of the sender button.
 
 @return IBAction  A possible return action to be done.
 */
- (IBAction)sliderChangeValue:(id)sender;

/*!
 @brief Changes the mPlaybackVol value in the SynthEngine to match the mPlaybackSlider value.
 
 @param sender  The id of the sender button.
 
 @return IBAction  A possible return action to be done.
 */
- (IBAction)playbackSliderChangeValue:(id)sender;

/*!
 @brief Changes the mRealtimeVol value in the SynthEngine to match the mRealtimeSlider value.
 
 @param sender  The id of the sender button.
 
 @return IBAction  A possible return action to be done.
 */
- (IBAction)realtimeSliderChangeValue:(id)sender;

/*!
 @brief Changes the mGrainType in SynthEngine to match the value of the selected dropdown menu option.
 
 @param sender  The id of the sender button.
 
 @return IBAction  A possible return action to be done.
 */
- (IBAction)dropdownChangeValue:(id)sender;

/*!
 @brief Toggles whether or not the finished SFX is played back.
 
 @param sender  The id of the sender button.
 
 @return IBAction  A possible return action to be done.
 */
- (IBAction)togglePlayback:(id)sender;

@end
