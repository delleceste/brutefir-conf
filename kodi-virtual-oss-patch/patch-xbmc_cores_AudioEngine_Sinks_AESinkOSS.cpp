--- xbmc/cores/AudioEngine/Sinks/AESinkOSS.cpp.orig
+++ xbmc/cores/AudioEngine/Sinks/AESinkOSS.cpp
@@ -16,6 +16,7 @@
 #include "utils/log.h"
 #include "threads/SingleLock.h"
 #include <sstream>
+#include <fstream>
 
 #include <sys/ioctl.h>
 #include <sys/fcntl.h>
@@ -536,6 +537,113 @@
     }
     info.m_wantsIECPassthrough = true;
     list.push_back(info);
+  }
+
+  /* Userspace OSS devices (e.g. cuse-based virtual_oss) are not kernel PCM
+   * cards, so they are not counted by SNDCTL_SYSINFO and the loop above never
+   * enumerates them.  Kodi then has no entry to match a user-selected device
+   * against, and the audio-device settings filler silently resets it to the
+   * first card.  /dev/sndstat is the only place these devices are advertised,
+   * so parse its "Installed devices from userspace:" section and probe each
+   * node the same way a kernel card is probed (open + SNDCTL_ENGINEINFO). */
+  {
+    std::ifstream sndstat("/dev/sndstat");
+    std::string sndline;
+    bool inUserspace = false;
+    while (std::getline(sndstat, sndline))
+    {
+      if (sndline.find("from userspace") != std::string::npos)
+      {
+        inUserspace = true;
+        continue;
+      }
+      if (!inUserspace)
+        continue;
+
+      const std::string::size_type colon = sndline.find(':');
+      if (colon == std::string::npos)
+        continue;
+
+      std::string node = sndline.substr(0, colon);
+      const std::string::size_type b = node.find_first_not_of(" \t");
+      const std::string::size_type e = node.find_last_not_of(" \t");
+      if (b == std::string::npos)
+        continue;
+      node = node.substr(b, e - b + 1);
+
+      CAEDeviceInfo info;
+      info.m_deviceName = "/dev/" + node;
+
+      /* skip anything already advertised as a kernel card */
+      bool duplicate = false;
+      for (const CAEDeviceInfo& known : list)
+        if (known.m_deviceName == info.m_deviceName)
+        {
+          duplicate = true;
+          break;
+        }
+      if (duplicate)
+        continue;
+
+      /* friendly name from the "<...>" description, if present */
+      const std::string::size_type lt = sndline.find('<');
+      const std::string::size_type gt = sndline.find('>', lt);
+      if (lt != std::string::npos && gt != std::string::npos && gt > lt)
+        info.m_displayName = node + " " + sndline.substr(lt + 1, gt - lt - 1);
+      else
+        info.m_displayName = node;
+
+      info.m_deviceType = AE_DEVTYPE_PCM;
+
+      /* Probe the node for real formats/channels/rates.  Enumeration must be
+       * non-destructive, so open non-blocking; if the device is busy or cannot
+       * be queried, fall back to conservative defaults rather than hiding it. */
+      int oformats = 0;
+      int maxChannels = 0;
+      int minRate = 0;
+      int maxRate = 0;
+      const int probefd = open(info.m_deviceName.c_str(), O_WRONLY | O_NONBLOCK, 0);
+      if (probefd != -1)
+      {
+#if defined(SNDCTL_ENGINEINFO)
+        oss_audioinfo ainfo = {};
+        ainfo.dev = -1;
+        if (ioctl(probefd, SNDCTL_ENGINEINFO, &ainfo) != -1)
+        {
+          oformats = ainfo.oformats;
+          maxChannels = ainfo.max_channels;
+          minRate = ainfo.min_rate;
+          maxRate = ainfo.max_rate;
+        }
+#endif
+        if (oformats == 0)
+          ioctl(probefd, SNDCTL_DSP_GETFMTS, &oformats);
+        close(probefd);
+      }
+
+#ifdef AFMT_FLOAT
+      if (oformats & AFMT_FLOAT)
+        info.m_dataFormats.push_back(AE_FMT_FLOAT);
+#endif
+#ifdef AFMT_S32_NE
+      if (oformats & AFMT_S32_NE)
+        info.m_dataFormats.push_back(AE_FMT_S32NE);
+#endif
+      if ((oformats & AFMT_S16_NE) || info.m_dataFormats.empty())
+        info.m_dataFormats.push_back(AE_FMT_S16NE);
+
+      if (maxChannels < 1)
+        maxChannels = 2;
+      for (int ch = 0; ch < maxChannels && AE_CH_NULL != OSSChannelMap[ch]; ++ch)
+        info.m_channels += OSSChannelMap[ch];
+
+      for (int* rate = OSSSampleRateList; *rate != 0; ++rate)
+        if (minRate == 0 || maxRate == 0 || (*rate >= minRate && *rate <= maxRate))
+          info.m_sampleRates.push_back(*rate);
+
+      info.m_wantsIECPassthrough = true;
+      list.push_back(info);
+    }
   }
 #endif
   close(mixerfd);
