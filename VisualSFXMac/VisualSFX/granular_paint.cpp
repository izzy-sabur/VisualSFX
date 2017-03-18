#include <fstream>
// #include <algorithm>
#include <complex>
#include <cstdlib>
#include <cmath>
#include <iostream>
#include <queue>
using namespace std;

struct fileheader
{
  char riff_label[4]; // (00) = {'R','I','F','F'}
  unsigned riff_size; // (04) = 36 + data_size
  char file_tag[4]; // (08) = {'W','A','V','E'}
  char fmt_label[4]; // (12) = {'f','m','t',' '}
  unsigned fmt_size; // (16) = 16
  unsigned short audio_format; // (20) = 1
  unsigned short channel_count; // (22) = 1 or 2
  unsigned sampling_rate; // (24) = (anything)
  unsigned bytes_per_second; // (28) = (see above)
  unsigned short bytes_per_sample; // (32) = (see above)
  unsigned short bits_per_sample; // (34) = 8 or 16
  char data_label[4]; // (36) = {'d','a','t','a'}
  unsigned data_size; // (40) = # bytes of data
};

int generate(int argc, char *argv[]) {

  if (argc < 2)
    return 0;

  fstream in(argv[1], ios_base::binary | ios_base::in);

  float duration = atof(argv[2]) + .05;

  //////////////////////////////////////////////////////////////////////////
  // opening and writing header to wav file

  fstream out("new_sound.wav", ios_base::binary | ios_base::out);

  fileheader newHead;
  newHead.riff_label[0] = 'R';
  newHead.riff_label[1] = 'I';
  newHead.riff_label[2] = 'F';
  newHead.riff_label[3] = 'F';

  newHead.file_tag[0] = 'W';
  newHead.file_tag[1] = 'A';
  newHead.file_tag[2] = 'V';
  newHead.file_tag[3] = 'E';

  newHead.fmt_label[0] = 'f';
  newHead.fmt_label[1] = 'm';
  newHead.fmt_label[2] = 't';
  newHead.fmt_label[3] = ' ';

  newHead.fmt_size = 16;
  newHead.audio_format = 1;
  newHead.channel_count = 2; // stereo
  newHead.sampling_rate = 44100;
  newHead.bytes_per_sample = 4;
  newHead.bits_per_sample = 16;
  newHead.bytes_per_second = newHead.sampling_rate * newHead.bytes_per_sample;

  newHead.data_label[0] = 'd';
  newHead.data_label[1] = 'a';
  newHead.data_label[2] = 't';
  newHead.data_label[3] = 'a';

  newHead.data_size = newHead.bytes_per_second * duration;
  newHead.riff_size = newHead.data_size + 36;

  char *header = reinterpret_cast<char*>(&newHead);

  out.write(header, 44);

  char* data = new char[newHead.data_size];

  unsigned count = newHead.data_size / 2;
  short *samples = reinterpret_cast<short*>(data);

  float* dataCopy = new float[count];
  for (unsigned i = 0; i < count; i++)
    dataCopy[i] = 0;
  //////////////////////////////////////////////////////////////////////////
  // opening and retrieving header from bmp

  char bmp_header[54];
  in.read(bmp_header, 54);
  int bmp_width = *(reinterpret_cast<int*>(bmp_header + 18)),
    bmp_height = *(reinterpret_cast<int*>(bmp_header + 22)),
    bmp_data_size = *(reinterpret_cast<int*>(bmp_header + 34)),
    bmp_stride = bmp_data_size / abs(bmp_height);

  // now reading bitmap

  char* bmp_data = new char[bmp_data_size];
  in.read(bmp_data, bmp_data_size);
  unsigned char *pixel = reinterpret_cast<unsigned char*>(bmp_data);

  int abs_height = abs(bmp_height);
  int abs_width = abs(bmp_width);

  const float PI = 4.0f*atan(1.0f),
    TWOPI = 2.0f*PI;
  //////////////////////////////////////////////////////////////////////////
  // now striding through bitmap and generating grains off rgb data

  // height loop
  for (int i = 0; i < abs_height; i++)
  {
    // width loop
    for (int j = 0; j < abs_width; j++)
    {
      // getting all the data for the grain
      unsigned char b = pixel[(bmp_stride * i) + (3 * j)],
        g = pixel[(bmp_stride * i) + (3 * j) + 1],
        r = pixel[(bmp_stride * i) + (3 * j) + 2];

      float freq = 40 * (pow(500.0f, i / (float)abs_height));

      float Y = (.299 * r) + (.587 * g) + (.114 * b),
        Cb = (-.169 * r) - (.331 * g) + (.499 * b) + 128,
        Cr = (.499 * r) - (.418 * g) - (.0813 * b) + 128;

      float amplitude = 1 - (Y / 255);
      float ampLeft = (Cb/255) * amplitude;
      float ampRight = (1 - (Cb/255)) * amplitude;

      float rNum = ((rand() % 1000) - 500) / 500.0f;
      float startTime = ((j + rNum) * (duration * 2)) / abs_width;
      float length = .01 + .09 * (Cr / 255);

      if (startTime < 0)
        startTime = 0;

      // now generating grain
      unsigned startTimeIndex = startTime * newHead.sampling_rate;
      unsigned indexLength = length * newHead.sampling_rate;
      float halfLeng = (indexLength * .5f);
      for (unsigned k = startTimeIndex; k < (startTimeIndex + indexLength); k += 2)
      {
        float env_factor = 1;
        unsigned env_switch = (k - startTimeIndex);

        if (env_switch < halfLeng)
          env_factor = env_switch / halfLeng;
        else
          env_factor = (indexLength - env_switch) / halfLeng;
        float curTime = (k / (float)newHead.sampling_rate);
        float rawSound = sin(TWOPI * curTime * freq) * env_factor;
        if (k < count)
        {
          dataCopy[k] += rawSound * ampLeft;
          dataCopy[k + 1] += rawSound * ampRight;
        }
      }
    }
  }

  //////////////////////////////////////////////////////////////////////////
  // now make sure the data doesn't peak

  // determine the max value we want to have
  float maxdB = ((96.0 - 15.0) / 96.0);
  short max16BitVal = ((1 << 15) - 1) * maxdB;

  float maxVal = 0;
  for (unsigned i = 0; i < count; i++)
  {
    if (dataCopy[i] > maxVal)
      maxVal = dataCopy[i];
  }

  // determine ratio between largest given number and max desired value
  float maxValRatio = max16BitVal / maxVal;

  // multiply everything by that ratio
  for (unsigned i = 0; i < count; i++)
  {
    dataCopy[i] *= maxValRatio;
    samples[i] = dataCopy[i];
  }

  // now write all the data
  out.write(data, newHead.data_size);





  delete[] data;
  delete[] dataCopy;
  return 0;
}
