//
//  SynthEngine.h
//  VisualSFX
//
//  Created by eightball on 10/17/16.
//  Copyright © 2016 Violin. All rights reserved.
//

/*!
 @header SynthEngine.h
 
 @brief The interface for the SynthEngine class, to be used for real-time granular synthesis of 
        SFX from image files.
 
 @author Izzy Abdus-Sabur
 @copyright  2016 Izzy Abdus-Sabur
 @version    0.1
 */

#import <Cocoa/Cocoa.h>
#import <CoreAudio/CoreAudio.h>
#import <AudioToolbox/AudioToolbox.h>

#define IZ_MAX_BUF_SIZE 4096
#define IZ_NUM_BUFF 2
#define EXTRA_DUR .2f
typedef struct AGData
{
    double              mBufferData[IZ_MAX_BUF_SIZE * IZ_NUM_BUFF];
    UInt32              mCurrSampleIndex;
    bool                mNewData;
} AGData;

typedef struct Grain
{
    float mFreq, mAmplitude;
    unsigned mStartIndex, mLength, mCurrSample;
    bool mOn;
} Grain;

typedef enum GrainType
{
    SineWave = 0,
    SquareWave,
    SawtoothWave,
    TriangleWave
} GrainType;

@interface SynthEngine : NSObject
{
    /*! @brief The CoreAudio graph, to be initialized when this class is initialized. */
    AUGraph     mAudioGraph;
    
    /*! @brief The output AudioUnit hooked up to mAudioGraph. */
    AudioUnit   mOutput;
    
    AudioFileID mCurrFile;
    NSURL* mFilePath;
    
    bool readingAudioData;
    UInt32 audioDataIndex;
    
@public
    /*! @brief A float value controlling the duration of the sound. */
    float mSoundDuration;
    
    /*! @brief A float value controlling the output volume of the SFX playback. */
    float mPlaybackVol;
    
    /*! @brief A float value controlling the output volume of the real-time synthesis playback. */
    float mRealtimeVol;
    
    /*! @brief An enum that changes the waveform used to generate grains. */
    GrainType mGrainType;
    
    /*! @brief A boolean that controls whether or not the sound effect is played back after the real-time synthesis ends. */
    bool mPlaybackOn;
}

/*!
 @brief The init function. Calls awakeFromNib.
 
 @return SynthEngine* A pointer to this instance.
 */
- (SynthEngine*)init;

/*!
 @brief The *real* init function. Sets initial values, allocates necessary values, and calls initializeGraph.
 */
- (void)awakeFromNib;

/*!
 @brief This initializes, configures, and starts mAudioGraph.
 */
- (void)initializeGraph;

/*!
 @brief This method calls renderBufferData, using mWriteableHeadIndex as a parameter. This method is called
        whenever the render callback buffer in mStreamData runs out of data.
 */
- (void)getBufferData;

/*!
 @brief This fills the buffer in mStreamData with the audio SFX data, if it is available.
 
 @param startIndex The start index of the writeable block in the mStreamData buffer.
 */
- (void)renderBufferData:(int)startIndex;

/*!
 @brief Starts creating grains from the given imageData and scheduling them in the grain array to be rendered.
        This function can be locked by the value of mFreeGrainCond.
 
 @param imageData A pointer to a buffer of imageData in a 32 bit ARGB format.
 @param sourceImage A reference to the image, to access its height and weight.
 */
- (void)createAudioDataFromImageData:(void*)imageData imageRef:(CGImageRef)sourceImage;

/*!
 @brief Takes the audio data in mAudioData and writes it to a WAV file.
 
 @param path The path to the image that the SFX was created from.
 */
- (void)writeAudioFileFromAudioData:(NSURL*)path;

/*!
 @brief This allocates and initializes mGrainArray and all the grain values.
 
 @param newWidth The width of the new image, so that the mGrainArray can be re-allocated to that size.
 */
- (void)initializeGrainArray:(size_t)newWidth;

/*!
 @brief Schedules a grain in mGrainArray.
 
 @param grainFreq  The frequency of the grain.
 @param amplitude  The amplitude of the grain.
 @param startIndex  The index where the grain should start being rendered.
 @param startLength  The length of the grain (in samples).
 
 @return bool  Returned whether or not the grain was successfully scheduled.
 */
- (bool)scheduleGrain:(float)grainFreq amplitude:(float)amplitude index:(unsigned)startIndex length:(unsigned)startLength;

/*!
 @brief Copies the data from mDataHold into mAudioData and normalizes it.
 */
- (void)copyFromDataHold;
@end
