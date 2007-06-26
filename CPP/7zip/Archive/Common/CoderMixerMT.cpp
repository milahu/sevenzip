// CoderMixerMT.cpp

#include "StdAfx.h"

#include "CoderMixerMT.h"

namespace NCoderMixer {

void CCoder::Execute() { Code(NULL); }

void CCoder::Code(ICompressProgressInfo *progress)
{
  Result = Coder->Code(InStream, OutStream, 
      InSizeAssigned ? &InSizeValue : NULL, 
      OutSizeAssigned ? &OutSizeValue : NULL, 
      progress);
  InStream.Release();
  OutStream.Release();
}

void CCoderMixerMT::AddCoder(ICompressCoder *coder)
{
  _coders.Add(CCoder());
  _coders.Back().Coder = coder;
}

void CCoderMixerMT::ReInit()
{
  for(int i = 0; i < _coders.Size(); i++)
    _coders[i].ReInit();
}

STDMETHODIMP CCoderMixerMT::Code(ISequentialInStream *inStream,
    ISequentialOutStream *outStream, 
    const UInt64 * /* inSize */, const UInt64 * /* outSize */,
    ICompressProgressInfo *progress)
{
  _coders.Front().InStream = inStream;
  int i;
  _coders.Back().OutStream = outStream;

  for (i = 0; i < _coders.Size(); i++)
    if (i != _progressCoderIndex)
    {
      RINOK(_coders[i].Create());
    }

  while (_streamBinders.Size() + 1 < _coders.Size())
  {
    _streamBinders.Add(CStreamBinder());
    int i = _streamBinders.Size() - 1;
    CStreamBinder &sb = _streamBinders.Back();
    RINOK(sb.CreateEvents());
    sb.CreateStreams(&_coders[i + 1].InStream, &_coders[i].OutStream);
  }

  for(i = 0; i < _streamBinders.Size(); i++)
    _streamBinders[i].ReInit();

  for (i = 0; i < _coders.Size(); i++)
    if (i != _progressCoderIndex)
      _coders[i].Start();

  _coders[_progressCoderIndex].Code(progress);

  for (i = 0; i < _coders.Size(); i++)
    if (i != _progressCoderIndex)
      _coders[i].WaitFinish();

  for (i = 0; i < _coders.Size(); i++)
  {
    HRESULT result = _coders[i].Result;
    if (result == E_ABORT)
      return result;
  }
  for (i = 0; i < _coders.Size(); i++)
  {
    HRESULT result = _coders[i].Result;
    if (result == S_FALSE)
      return result;
  }
  for (i = 0; i < _coders.Size(); i++)
  {
    HRESULT result = _coders[i].Result;
    if (result != S_OK && result != E_FAIL)
      return result;
  }
  for (i = 0; i < _coders.Size(); i++)
  {
    HRESULT result = _coders[i].Result;
    if (result != S_OK)
      return result;
  }
  return S_OK;
}

}  
