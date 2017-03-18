//
//  SynthEnginePrivate.h
//  VisualSFX
//
//  Created by Violin on 10/19/16.
//  Copyright © 2016 Violin. All rights reserved.
//

#include "SynthEngine.h"

/*!
 @header SynthEnginePrivate.h
 
 @brief All of these values are public so that the render callback can access them;
 they're for internal use by the SynthEngine class only.
 
 @author Izzy Abdus-Sabur
 @copyright  2016 Izzy Abdus-Sabur
 @version    0.1
 */

@interface SynthEngine ()
{
@public
    /*! @brief A struct holding the buffer data to be used in the AudioGraph render callback. */
    AGData      mStreamData;
    
    /*! @brief The sample rate of the SFX and audio playback. */
    UInt32      mSampleRate;
    
    /*! @brief Indexes into the buffer data; this one points to the start of a buffer of data that is writeable. */
    UInt32      mWriteableHeadIndex;
    
    /*! @brief Indexes into the buffer data; this one points to the end of a buffer of data that is readable. */
    SInt32      mReadableEndIndex;
    
    /*! @brief The number of bytes of audio data per frame. */
    int mBytesPerFrame;

    
    
    
    
    
    /*! @brief An array of grains. This is used by the render callback to render granular synthesis real-time. */
    Grain* mGrainArray;
    
    /*! @brief The width of the grain array. */
    size_t mGrainArrayWidth;
    
    /*! @brief The index of the last unscheduled grain found. (For scheduling optimization) */
    size_t mLastGrainIndex;
    
    /*! @brief A value representing the largest possible number of grains at the same point in time (for volume control to prevent peaking) */
    size_t mMaxConcurrentGrains;
    
    /*! @brief A boolean value signaling if the granular synthesis render has rendered all grains in the given picture. */
    bool mRenderDone;
    
    /*! @brief A boolean value signaling if the grain scheduler has scheduled all grains in the given picture. */
    bool mScheduleDone;
    
    /*! @brief The timestamp of when the scheduler started running. Used to calculate when a grain should be played, based off their mStartIndex. */
    UInt64 mStartTimeStamp;
    
    /*! @brief The minimum time offset (secs) to be added to the mStartTimeStamp to ensure that the renderer array is full of grains before it starts. */
    float mStartOffset;
    
    
    
    /*! @brief A boolean paired with mFreeGrainCond, the condition used to signal that there are free spots for grains to be scheduled. */
    bool mGrainFree;
    
    /*! @brief An NSCondition used to let the render callback signal the scheduler when there are new free spots for grains to be scheduled. */
    NSCondition *mFreeGrainCond;
    
    
    
    
    
    /*! @brief An array containing the normalized synthesis values from the image for the SFX. */
    short* mAudioData;
    
    /*! @brief An array containing the raw synthesis values from the image for the SFX. */
    float* mDataHold;

    /*! @brief This stores the value of mSoundDuration once rendering begins, so that the values don't change mid-render. */
    float mInitSoundDuration;
    
    /*! @brief This stores the value of mGrainType once rendering begins, so that the values don't change mid-render. */
    GrainType mInitGrainType;
}
@end