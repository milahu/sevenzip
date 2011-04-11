// RegistryAssociations.cpp

#include "StdAfx.h"

#include "Common/IntToString.h"
#include "Common/StringConvert.h"
#include "Common/StringToInt.h"

#include "Windows/Registry.h"

#include "RegistryAssociations.h"

using namespace NWindows;
using namespace NRegistry;

namespace NRegistryAssoc {
  
// static NSynchronization::CCriticalSection g_CriticalSection;

static const TCHAR *kClasses = TEXT("Software\\Classes\\");
// static const TCHAR *kShellNewKeyName = TEXT("ShellNew");
// static const TCHAR *kShellNewDataValueName = TEXT("Data");
static const TCHAR *kDefaultIconKeyName = TEXT("DefaultIcon");
static const TCHAR *kShellKeyName = TEXT("shell");
static const TCHAR *kOpenKeyName = TEXT("open");
static const TCHAR *kCommandKeyName = TEXT("command");
static const TCHAR *k7zipPrefix = TEXT("7-Zip.");

static CSysString GetExtProgramKeyName(const CSysString &ext)
{
  return CSysString(k7zipPrefix) + ext;
}

static CSysString GetFullKeyPath(HKEY hkey, const CSysString &name)
{
  CSysString s;
  if (hkey != HKEY_CLASSES_ROOT)
    s = kClasses;
  return s + name;
}

static CSysString GetExtKeyPath(HKEY hkey, const CSysString &ext)
{
  return GetFullKeyPath(hkey, (TEXT(".")) + ext);
}

bool CShellExtInfo::ReadFromRegistry(HKEY hkey, const CSysString &ext)
{
  ProgramKey.Empty();
  IconPath.Empty();
  IconIndex = -1;
  // NSynchronization::CCriticalSectionLock lock(g_CriticalSection);
  {
    CKey extKey;
    if (extKey.Open(hkey, GetExtKeyPath(hkey, ext), KEY_READ) != ERROR_SUCCESS)
      return false;
    if (extKey.QueryValue(NULL, ProgramKey) != ERROR_SUCCESS)
      return false;
  }
  {
    CKey iconKey;
    if (iconKey.Open(hkey, GetFullKeyPath(hkey, ProgramKey + CSysString(TEXT(CHAR_PATH_SEPARATOR)) + kDefaultIconKeyName), KEY_READ) == ERROR_SUCCESS)
    {
      UString value;
      if (iconKey.QueryValue(NULL, value) == ERROR_SUCCESS)
      {
        int pos = value.ReverseFind(L',');
        IconPath = value;
        if (pos >= 0)
        {
          const wchar_t *end;
          Int64 index = ConvertStringToInt64((const wchar_t *)value + pos + 1, &end);
          if (*end == 0)
          {
            IconIndex = (int)index;
            IconPath = value.Left(pos);
          }
        }
      }
    }
  }
  return true;
}

bool CShellExtInfo::IsIt7Zip() const
{
  UString s = GetUnicodeString(k7zipPrefix);
  return (s.CompareNoCase(GetUnicodeString(ProgramKey.Left(s.Length()))) == 0);
}

LONG DeleteShellExtensionInfo(HKEY hkey, const CSysString &ext)
{
  // NSynchronization::CCriticalSectionLock lock(g_CriticalSection);
  CKey rootKey;
  rootKey.Attach(hkey);
  LONG res = rootKey.RecurseDeleteKey(GetExtKeyPath(hkey, ext));
  // then we delete only 7-Zip.* key.
  rootKey.RecurseDeleteKey(GetFullKeyPath(hkey, GetExtProgramKeyName(ext)));
  rootKey.Detach();
  return res;
}

LONG AddShellExtensionInfo(HKEY hkey,
    const CSysString &ext,
    const UString &programTitle,
    const UString &programOpenCommand,
    const UString &iconPath, int iconIndex
    // , const void *shellNewData, int shellNewDataSize
    )
{
  LONG res = 0;
  DeleteShellExtensionInfo(hkey, ext);
  // NSynchronization::CCriticalSectionLock lock(g_CriticalSection);
  CSysString programKeyName;
  {
    CSysString ext2 = ext;
    if (iconIndex < 0)
      ext2 = TEXT("*");
    programKeyName = GetExtProgramKeyName(ext2);
  }
  {
    CKey extKey;
    res = extKey.Create(hkey, GetExtKeyPath(hkey, ext));
    extKey.SetValue(NULL, programKeyName);
    /*
    if (shellNewData != NULL)
    {
      CKey shellNewKey;
      shellNewKey.Create(extKey, kShellNewKeyName);
      shellNewKey.SetValue(kShellNewDataValueName, shellNewData, shellNewDataSize);
    }
    */
  }
  CKey programKey;
  programKey.Create(hkey, GetFullKeyPath(hkey, programKeyName));
  programKey.SetValue(NULL, programTitle);
  {
    CKey iconKey;
    UString iconPathFull = iconPath;
    if (iconIndex < 0)
      iconIndex = 0;
    // if (iconIndex >= 0)
    {
      iconPathFull += L',';
      wchar_t s[16];
      ConvertInt64ToString(iconIndex, s);
      iconPathFull += s;
    }
    iconKey.Create(programKey, kDefaultIconKeyName);
    iconKey.SetValue(NULL, iconPathFull);
  }

  CKey shellKey;
  shellKey.Create(programKey, kShellKeyName);
  shellKey.SetValue(NULL, TEXT(""));

  CKey openKey;
  openKey.Create(shellKey, kOpenKeyName);
  openKey.SetValue(NULL, TEXT(""));
  
  CKey commandKey;
  commandKey.Create(openKey, kCommandKeyName);
  commandKey.SetValue(NULL, programOpenCommand);
  return res;
}

}
