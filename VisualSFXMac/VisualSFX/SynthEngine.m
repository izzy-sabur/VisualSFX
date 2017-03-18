//
//  SynthEngine.m
//  VisualSFX
//
//  Created by eightball on 10/17/16.
//  Copyright © 2016 Violin. All rights reserved.
//

#import "SynthEngine.h"
#import "SynthEnginePrivate.h"
#import <AudioUnit/AudioUnitParameters.h>
#import <AudioUnit/AudioUnitProperties.h>

#define TO_NANOSECONDS 1000000000

float squareSound(float pos)
{
    return (floorf(pos + .5f) * 2.0f) - 1;
}

float sawSound(float pos)
{
    return (pos * 2.0f) - 1;
}

float triSound(float pos)
{
    return (1 - (fabs(pos - .5) * 4));
}

float sinSound(float x)
{
    return sin(x * 2.0f * 3.1415926535f);
}

//////////////////////////////
// RENDER CALLBACK FUNCTION //
//////////////////////////////
OSStatus renderInput(void* inRefCon,
                     AudioUnitRenderActionFlags *ioActionFlags,
                     const AudioTimeStamp *inTimeStamp,
                     UInt32 inBusNumber,
                     UInt32 inNumberFrames,
                     AudioBufferList *ioData)
{
    float *outBuf = (float*)ioData->mBuffers[0].mData;
    SynthEngine *engine = (__bridge SynthEngine*)inRefCon;
    int currSampleIndex = engine->mStreamData.mCurrSampleIndex;
    
    size_t arrayWidth = engine->mGrainArrayWidth;
    bool grainsLeft = false, freedGrain = false;
    UInt64 dataSize = engine->mSampleRate * engine->mBytesPerFrame * (engine->mInitSoundDuration + EXTRA_DUR);
    
    memset(outBuf, 0, ioData->mBuffers[0].mDataByteSize);
    float maxdB = ((96.0 - 15.0) / 96.0);
    short max16BitVal = ((1 << 15) - 1) * maxdB;
    float volMult = 0, shortVolMult = 0;
    
    if(engine->mMaxConcurrentGrains != 0)
    {
        volMult = 0.5f / engine->mMaxConcurrentGrains;
        shortVolMult = max16BitVal / engine->mMaxConcurrentGrains;
    }
    
    // check if there are any grains to render
    for(size_t i = 0; i < arrayWidth; i++)
    {
        
        // check if it's on
        if (!engine->mGrainArray[i].mOn)
        {
            continue;
        }
        
        grainsLeft = true;
        
        // render out a few frames of data
        float freq = engine->mGrainArray[i].mFreq,
        amplitude = engine->mGrainArray[i].mAmplitude;
        
        // check the start time index
        unsigned startTimeIndex = engine->mGrainArray[i].mStartIndex;
        
        // if the start timestamp + start index > current timestamp (if it's not the time to play this grain), continue
        UInt64 startTime = (((startTimeIndex * 1.0f) / engine->mSampleRate) * TO_NANOSECONDS) + engine->mStartTimeStamp,
        curTime = AudioConvertHostTimeToNanos(inTimeStamp->mHostTime);
        
        
        if(startTime > curTime)
            continue;
        
        unsigned indexLength = engine->mGrainArray[i].mLength,
        curSample = engine->mGrainArray[i].mCurrSample,
        curIndex = curSample + startTimeIndex,
        endIndex = curIndex + inNumberFrames,
        actualEndIndex = indexLength + startTimeIndex;
        
        float halfLeng = (indexLength * .5f),
        grainVolMult = volMult * amplitude * engine->mRealtimeVol;
        
        
        float(*soundFunc)(float) = NULL;
        
        switch(engine->mInitGrainType)
        {
            case SineWave:
                soundFunc = &sinSound;
                break;
            case SquareWave:
                soundFunc = &squareSound;
                break;
            case SawtoothWave:
                soundFunc = &sawSound;
                break;
            case TriangleWave:
                soundFunc = &triSound;
                break;
        }
        
        for (unsigned k = curIndex; k < endIndex; k ++)
        {
            // remember to clear any grains that are left
            if(k >= actualEndIndex)
            {
                engine->mGrainArray[i].mOn = false;
                freedGrain = true;
                break;
            }
            float env_factor = 1;
            unsigned env_switch = (k - startTimeIndex);
            
            if (env_switch < halfLeng)
                env_factor = env_switch / halfLeng;
            else
                env_factor = (indexLength - env_switch) / halfLeng;
            float curTime = (k / (float)engine->mSampleRate);
            
            
            float rawSound = 0;
            float pos = fmodf(freq * curTime, 1.0);
            rawSound = soundFunc(pos) * env_factor;
            
            if (k < dataSize)
            {
                outBuf[k - curIndex] += (rawSound * grainVolMult);
                engine->mDataHold[k] += (rawSound * amplitude);
            }
            
        }
        engine->mGrainArray[i].mCurrSample = endIndex - startTimeIndex;
        
    }
    // if there are any new free grains, unlock the grain conditional
    if(freedGrain)
    {
        if(!engine->mGrainFree)
        {
            engine->mGrainFree = true;
            [engine->mFreeGrainCond signal];
        }
        freedGrain = false;
    }
    
    
    
    
    
    // if there were no grains, just copy from the bufer
    if(!grainsLeft && engine->mPlaybackOn)
    {
        if(engine->mScheduleDone && !engine->mRenderDone)
        {
            engine->mRenderDone = true;
            [engine copyFromDataHold];
        }
        
        for(int i = 0; i < inNumberFrames; i++)
        {
            // if we don't have any new data
            if(!engine->mStreamData.mNewData)
            {
                // output silence
                outBuf[i] = 0.0f;
                continue;
            }
            
            // if we've gotten to the end of the buffer
            if(currSampleIndex >= engine->mReadableEndIndex)
            {
                // set us to the start of the next writable buffer
                engine->mStreamData.mCurrSampleIndex = engine->mWriteableHeadIndex;
                currSampleIndex = engine->mWriteableHeadIndex;
                
                // step over the end mark and the beginning mark by one buffer size
                engine->mReadableEndIndex += IZ_MAX_BUF_SIZE;
                engine->mReadableEndIndex %= IZ_MAX_BUF_SIZE * IZ_NUM_BUFF;
                
                engine->mWriteableHeadIndex += IZ_MAX_BUF_SIZE;
                engine->mWriteableHeadIndex %= IZ_MAX_BUF_SIZE * IZ_NUM_BUFF;
                
                
                [engine getBufferData];
            }
            outBuf[i] = engine->mStreamData.mBufferData[currSampleIndex++] * engine->mPlaybackVol;
            engine->mStreamData.mCurrSampleIndex++;
        }
    }
    
    // for every extra buffer, copy the data over
    for(int i = 1; i < ioData->mNumberBuffers; i++)
    {
        memcpy(ioData->mBuffers[i].mData, ioData->mBuffers[0].mData, ioData->mBuffers[0].mDataByteSize);
    }
    return noErr;
}

//////////////////////////////


@implementation SynthEngine

- (SynthEngine*)init
{
    [self awakeFromNib];
    return self;
}

- (void)awakeFromNib
{
    mSampleRate = 48000;
    mReadableEndIndex = -1;
    mWriteableHeadIndex = 0;
    mStreamData.mNewData = true;
    mBytesPerFrame = 2;
    mSoundDuration = 4;
    mGrainType = SineWave;
    mPlaybackOn = true;
    mStartOffset = 1.0f;
    
    mLastGrainIndex = 0, mGrainArrayWidth = 0, mGrainArray = NULL;
    mFilePath = [[NSURL alloc] init];
    mFreeGrainCond = [[NSCondition alloc] init];
    [self initializeGraph];
}

- (void)getBufferData
{
    // this calls some callback to get more samples
    [self renderBufferData:mWriteableHeadIndex];
}

- (void)renderBufferData:(int)startIndex
{
    float maxdB = ((96.0 - 15.0) / 96.0);
    float max16BitVal = ((1 << 15) - 1) * maxdB;
    for(int i = 0; i < IZ_MAX_BUF_SIZE; i++)
    {
        if(readingAudioData)
        {
            float thisFrameData = mAudioData[audioDataIndex++];
            float toFloat = thisFrameData / max16BitVal;
            mStreamData.mBufferData[startIndex + i] = toFloat;
            
            if(audioDataIndex >= (mSampleRate * (mInitSoundDuration + EXTRA_DUR)))
            {
                readingAudioData = false;
            }
        }
        else
        {
            //float timeInc = i/(float)IZ_MAX_BUF_SIZE;
            mStreamData.mBufferData[startIndex + i] = 0.0f;//sinf(3.14159 * 2 * 100 * timeInc) / 2.0f;
        }
    }
}

- (void)copyFromDataHold
{
    UInt64 dataSize = mSampleRate * mBytesPerFrame * (mInitSoundDuration + EXTRA_DUR);
    
    // determine the max value we want to have
    float maxdB = ((96.0 - 15.0) / 96.0);
    short max16BitVal = ((1 << 15) - 1) * maxdB;

    float maxVal = 0;
    for (unsigned i = 0; i < dataSize; i++)
    {
        float val = mDataHold[i];
        if (val > maxVal)
            maxVal = val;
    }

    // determine ratio between largest given number and max desired value
    float maxValRatio = max16BitVal / maxVal;

    // multiply everything by that ratio
    for (unsigned i = 0; i < dataSize; i++)
    {
        mDataHold[i] *= maxValRatio;
        mAudioData[i] = mDataHold[i];
    }
}

- (void)createAudioDataFromImageData:(void*)imageData imageRef:(CGImageRef)sourceImage
{
    size_t pixelsWide = CGImageGetWidth(sourceImage);
    size_t pixelsHigh = CGImageGetHeight(sourceImage);
    
    
    size_t bytesPerPixel = 4;
    size_t bytesPerRow = bytesPerPixel * pixelsWide;
    
    // don't render the same data twice
    if((pixelsHigh == mMaxConcurrentGrains) && (mAudioData != NULL) && (mSoundDuration == mInitSoundDuration) && (mInitGrainType == mGrainType) && (mPlaybackOn))
    {
        readingAudioData = true;
        audioDataIndex = 0;
        return;
    }
    
    mInitGrainType = mGrainType;
    mMaxConcurrentGrains = pixelsHigh;
    mRenderDone = false;
    
    [self initializeGrainArray:pixelsWide];
    
    if(mAudioData != NULL)
        free(mAudioData);
    
    if(mDataHold != NULL)
        free(mDataHold);
    
    // create a hold for the audio data
    mInitSoundDuration = mSoundDuration;
    UInt64 dataSize = mSampleRate * mBytesPerFrame * (mInitSoundDuration + EXTRA_DUR);
    
    mAudioData = calloc(dataSize, sizeof(short));
    mDataHold = calloc(dataSize, sizeof(float));
    
    mScheduleDone = false;
    
    // register the timestamp, add the offset
    mStartTimeStamp = AudioConvertHostTimeToNanos(AudioGetCurrentHostTime());
    mStartTimeStamp += mStartOffset * TO_NANOSECONDS;
    
    for(size_t i = 0; i < pixelsWide; i++)
    {
        //printf("\n Column %2zu: ", i);
        
        
        for(size_t j = 0; j < pixelsHigh; j++)
        {
            //unsigned char* alphaValAddress =   (imageData + (j*bytesPerPixel) + (i * bytesPerRow));
            unsigned char* redValAddress = (imageData + (j*bytesPerRow) + (i * bytesPerPixel) + 1);
            unsigned char* greenValAddress =  (imageData + (j*bytesPerRow) + (i * bytesPerPixel) + 2);
            unsigned char* blueValAddress = (imageData + (j*bytesPerRow) + (i * bytesPerPixel) + 3);
            
            unsigned char r = *redValAddress;
            unsigned char g = *greenValAddress;
            unsigned char b = *blueValAddress;
            //unsigned char a = *alphaValAddress;
            
            if((r + g + b) == 765)
                continue;
            
            //printf("P%2zu:(%3u,%3u,%3u) ", j,r,g,b);
            
            float Y = (.299 * r) + (.587 * g) + (.114 * b),
            //Cb = (-.169 * r) - (.331 * g) + (.499 * b) + 128,
            Cr = (.499 * r) - (.418 * g) - (.0813 * b) + 128;
            
            float freq = 40 * (pow(500.0f, (pixelsHigh - j) / (float)pixelsHigh));
            float amplitude = 1 - (Y / 255) ;
            //float ampLeft = (Cb/255) * amplitude;
            //float ampRight = (1 - (Cb/255)) * amplitude;
            
            float rNum = ((rand() % 1000) - 500) / 500.0f;
            float startTime = ((i + rNum) * (mInitSoundDuration)) / pixelsWide;
            float length = .01 + .09 * (Cr / 255);
            
            if (startTime < 0)
                startTime = 0;
            
            // now generating grain
            unsigned startTimeIndex = startTime * mSampleRate;
            unsigned indexLength = length * mSampleRate;
            //float halfLeng = (indexLength * .5f);
            
            
            mGrainFree = [self scheduleGrain:freq amplitude:amplitude index:startTimeIndex length:indexLength];
            
            // if there was no grain free, lock this thread
            while(!mGrainFree)
            {
                [mFreeGrainCond lock];
                [mFreeGrainCond wait];
                [mFreeGrainCond unlock];
                
                mGrainFree = [self scheduleGrain:freq amplitude:amplitude index:startTimeIndex length:indexLength];
            }
        }
        audioDataIndex = 0;

    }
    
    mScheduleDone = true;
    readingAudioData = true;
    audioDataIndex = 0;
}


- (void)writeAudioFileFromAudioData:(NSURL *)path
{
    // check to make sure we have some data
    if(mAudioData == NULL)
        return;
    
    // set the file description (mono wav)
    int bytes = 2;
    int channels = 1;
    int packetsize = 1;
    
    AudioStreamBasicDescription desc;
    desc.mSampleRate = mSampleRate;
    desc.mFormatID = kAudioFormatLinearPCM;
    desc.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    desc.mFramesPerPacket = packetsize;
    desc.mBytesPerFrame = bytes * channels;
    desc.mBitsPerChannel = bytes * 8;
    desc.mBytesPerPacket = desc.mBytesPerFrame * desc.mFramesPerPacket;
    desc.mChannelsPerFrame = channels;
    desc.mReserved = 0;
    
    // set the file path and create the file
    NSString* filename = [[NSString alloc] init];
    filename = [path.path stringByReplacingOccurrencesOfString:path.pathExtension withString:@"wav"];
    NSURL* filePath = [[NSURL alloc]initFileURLWithPath:filename];
    
    OSStatus err = AudioFileCreateWithURL((__bridge CFURLRef _Nonnull)(filePath), kAudioFileWAVEType, &desc, kAudioFileFlags_EraseFile, &mCurrFile);
    
    if(err != kAudioServicesNoError)
        err = 0;
    
    UInt32 numPackets = mSampleRate * (mInitSoundDuration + EXTRA_DUR);
    AudioFileWritePackets(mCurrFile, false, desc.mBytesPerPacket, NULL, 0, &numPackets, mAudioData);
    AudioFileClose(mCurrFile);
}


- (void)initializeGrainArray:(size_t)newWidth
{
    // reallocate the array if need be
    if(mGrainArray != NULL)
    {
        if(mGrainArrayWidth < newWidth)
        {
            free(mGrainArray);
            mGrainArray = malloc(sizeof(Grain) * newWidth);
            mGrainArrayWidth = newWidth;
        }
    }
    else
    {
        mGrainArray = malloc(sizeof(Grain) * newWidth);
        mGrainArrayWidth = newWidth;
    }
    
    // reset all array values
    for(size_t i = 0; i < mGrainArrayWidth; i++)
    {
        mGrainArray[i].mOn = false;
    }
    
    mGrainFree = true;
}

- (bool)scheduleGrain:(float)grainFreq amplitude:(float)amplitude index:(unsigned)startIndex length:(unsigned)startLength
{
    // search the array for a grain that's off, starting from the last grain we found
    for(size_t i = mLastGrainIndex; i < mGrainArrayWidth; i++)
    {
        if(!mGrainArray[i].mOn)
        {
            // and then reset its values
            mGrainArray[i].mFreq = grainFreq;
            mGrainArray[i].mAmplitude = amplitude;
            mGrainArray[i].mLength = startLength;
            mGrainArray[i].mStartIndex = startIndex;
            mGrainArray[i].mCurrSample = 0;
            mGrainArray[i].mOn = true;
            mLastGrainIndex = i;
            return true;
        }
    }
    
    // if we got to the end of the array and there was nothing, search the rest
    for(size_t i = 0; i < mLastGrainIndex; i++)
    {
        if(!mGrainArray[i].mOn)
        {
            // and then reset its values
            mGrainArray[i].mFreq = grainFreq;
            mGrainArray[i].mAmplitude = amplitude;
            mGrainArray[i].mLength = startLength;
            mGrainArray[i].mStartIndex = startIndex;
            mGrainArray[i].mCurrSample = 0;
            mGrainArray[i].mOn = true;
            mLastGrainIndex = i;
            return true;
        }
    }
    
    // if there were absolutely no spots, then return false
    return false;
}

// initializing the audio unit graph and subsequent audio units
- (void)initializeGraph
{
    // initialize the graph
    OSStatus result = noErr;
    result = NewAUGraph(&mAudioGraph);
    
    // setting the audio unit description and creating the node
    struct AudioComponentDescription desc;
    AUNode outputNode;
    
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_DefaultOutput;
    desc.componentFlags = kAudioComponentFlag_SandboxSafe;
    desc.componentFlagsMask = 0;
    
    // adding the node with the proper description
    result = AUGraphAddNode(mAudioGraph, &desc, &outputNode);
    if (result) {
        printf("AUGraphAddNode result: %lu %4.4s\n", (unsigned long)result, (char*)&result);
        return;
    }
    
    // opening the graph
    result = AUGraphOpen(mAudioGraph);
    if (result) {
        printf("AUGraphOpen result: %u %4.4s\n", (unsigned int)result, (char*)&result);
        return;
    }
    
    // getting the node info to save in the output audio unit
    result = AUGraphNodeInfo(mAudioGraph, outputNode, NULL, &mOutput);
    if (result) {
        printf("AUGraphNodeInfo result: %u %4.4s\n", (unsigned int)result, (char*)&result);
        return;
    }
    
    
    // set input and output bus counts
    UInt32 numbuses = 1;
    result = AudioUnitSetProperty(mOutput,
                                  kAudioUnitProperty_ElementCount,
                                  kAudioUnitScope_Input,
                                  0,
                                  &numbuses,
                                  sizeof(UInt32) );
    if(result)
    {
        printf("AUGraph SetInputBuses result: %u %4.4s\n", (unsigned) result, (char*)&result );
    }
    
    result = AudioUnitSetProperty(mOutput,
                                  kAudioUnitProperty_ElementCount,
                                  kAudioUnitScope_Output,
                                  0,
                                  &numbuses,
                                  sizeof(UInt32) );
    if(result)
    {
        printf("AUGraph SetOutputBuses result: %u %4.4s\n", (unsigned) result, (char*)&result );
    }
    
    // set render callback
    AURenderCallbackStruct rcbs;
    rcbs.inputProc = &renderInput;
    rcbs.inputProcRefCon = (__bridge void * _Nullable)(self);
    result = AudioUnitSetProperty(mOutput,
                                  kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Input,
                                  0,
                                  &rcbs,
                                  sizeof(rcbs));
    if(result)
    {
        printf("AUGraph SetRenderCallback result: %u %4.4s\n", (unsigned) result, (char*)&result );
    }
    
    
    struct AudioStreamBasicDescription streamDesc, newDesc;
    
    // get input stream format
    UInt32 size = sizeof(newDesc);
    result = AudioUnitGetProperty(mOutput,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  0,
                                  &newDesc,
                                  &size );
    
    printf(" --------- Audio Stream Description : Input --------- \n");
    printf("Sample Rate: %f \n", newDesc.mSampleRate);
    printf("Channels Per Frame: %u \n", (unsigned int)newDesc.mChannelsPerFrame);
    printf("Bytes Per Frame: %u \n", (unsigned int)newDesc.mBytesPerFrame);
    printf("Bytes Per Packet: %u \n", (unsigned int)newDesc.mBytesPerPacket);
    printf("Bits Per Channel: %u \n\n", (unsigned int)newDesc.mBitsPerChannel);

    result = AudioUnitGetProperty(mOutput,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  0,
                                  &streamDesc,
                                  &size );
    
    printf(" --------- Audio Stream Description : Output --------- \n");
    printf("Sample Rate: %f \n", streamDesc.mSampleRate);
    printf("Channels Per Frame: %u \n", (unsigned int)streamDesc.mChannelsPerFrame);
    printf("Bytes Per Frame: %u \n", (unsigned int)streamDesc.mBytesPerFrame);
    printf("Bytes Per Packet: %u \n", (unsigned int)streamDesc.mBytesPerPacket);
    printf("Bits Per Channel: %u \n\n", (unsigned int)streamDesc.mBitsPerChannel);
    
    if(result)
    {
        printf("AUGraph SetStreamFormat result: %u %4.4s\n", (unsigned) result, (char*)&result );
    }

    // set input stream format
    newDesc.mSampleRate = mSampleRate;
    
    result = AudioUnitSetProperty(mOutput,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  0,
                                  &newDesc,
                                  size );
    
    result = AudioUnitSetProperty(mOutput,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  0,
                                  &newDesc,
                                  size );
    
    // set buffer size
    UInt32 bufferSize = 512;
    result = AudioUnitSetProperty(mOutput,
                                  kAudioDevicePropertyBufferFrameSize,
                                  kAudioUnitScope_Input,
                                  0,
                                  &bufferSize,
                                  sizeof(UInt32));
    if(result)
    {
        printf("AUGraph SetBufferFrameSize result: %u %4.4s\n", (unsigned) result, (char*)&result );
    }
    
    
    // set output stream format
    result = AudioUnitGetProperty(mOutput,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  0,
                                  &streamDesc,
                                  &size );
    if(result)
    {
        printf("%u %4.4s\n", (unsigned) result, (char*)&result );
    }
    
    
    // now start the graph
    AUGraphInitialize(mAudioGraph);
    AUGraphStart(mAudioGraph);
    CAShow(mAudioGraph);
    
}

@end