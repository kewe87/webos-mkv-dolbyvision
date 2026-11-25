#!/usr/bin/env python3
# Applies the Dolby Vision profile 7 -> 8.1 conversion to LG's webOS 25
# matroskademux (GStreamer 1.24.0, lgstreamer/gstreamer-webos-25).
# LG's code already handles DV detection + caps for profiles 4/5/8/9/10;
# only the profile 7 branch ("play as HDR10") is replaced.
import re, sys, pathlib

src = pathlib.Path(sys.argv[1])
patch = pathlib.Path(sys.argv[2]).read_text()


def sub_once(text, old, new, what):
    n = text.count(old)
    if n != 1:
        sys.exit(f"{what}: anchor found {n}x")
    return text.replace(old, new)


# --- converter block taken verbatim from the webOS 22 patch ---------------
m = re.search(r"^\+#ifdef DOLBYHDR_P7_TO_P81\n(.*?)^\+#endif\n", patch, re.S | re.M)
conv = "#ifdef DOLBYHDR_P7_TO_P81\n" + "".join(
    l[1:] + "\n" for l in m.group(1).splitlines()) + "#endif\n"

log = '''#define MATROSKA_DV_LOG "/tmp/matroska-dv.log"

static void
matroska_dv_log (const gchar * format, ...)
    G_GNUC_PRINTF (1, 2);

static void
matroska_dv_log (const gchar * format, ...)
{
  FILE *f;
  va_list args;

  f = fopen (MATROSKA_DV_LOG, "a");
  if (f == NULL)
    return;

  va_start (args, format);
  vfprintf (f, format, args);
  va_end (args);
  fputc ('\\n', f);
  fclose (f);
}

'''

# --- matroska-demux.h ------------------------------------------------------
h = (src / "matroska-demux.h").read_text()
h = sub_once(h, "/* DolbyHDR support */\n#define DOLBYHDR_SUPPORT\n",
             "/* DolbyHDR support */\n#define DOLBYHDR_SUPPORT\n"
             "/* Convert Dolby Vision profile 7 to 8.1 on the fly (libdovi, dovi_tool mode 2) */\n"
             "#define DOLBYHDR_P7_TO_P81\n", "demux.h define")
(src / "matroska-demux.h").write_text(h)

# --- matroska-ids.h / .c ---------------------------------------------------
ih = (src / "matroska-ids.h").read_text()
ih = sub_once(ih, "  gint valid_color;\n} GstMatroskaTrackVideoContext;",
              "  gint valid_color;\n\n"
              "  /* Dolby Vision profile 7 -> 8.1 conversion (matroskademux) */\n"
              "  gboolean      dovi_p7_to_p81;\n  guint         dovi_nal_length_size;\n"
              "  guint64       dovi_frames;\n  guint64       dovi_rpu_converted;\n"
              "  guint64       dovi_rpu_failed;\n  guint64       dovi_el_dropped;\n"
              "} GstMatroskaTrackVideoContext;", "ids.h struct")
(src / "matroska-ids.h").write_text(ih)

ic = (src / "matroska-ids.c").read_text()
ic = sub_once(ic, "  video_context->multiview_flags = GST_VIDEO_MULTIVIEW_FLAGS_NONE;\n",
              "  video_context->multiview_flags = GST_VIDEO_MULTIVIEW_FLAGS_NONE;\n"
              "  video_context->dovi_p7_to_p81 = FALSE;\n  video_context->dovi_nal_length_size = 0;\n"
              "  video_context->dovi_frames = 0;\n  video_context->dovi_rpu_converted = 0;\n"
              "  video_context->dovi_rpu_failed = 0;\n  video_context->dovi_el_dropped = 0;\n",
              "ids.c init")
(src / "matroska-ids.c").write_text(ic)

# --- matroska-demux.c ------------------------------------------------------
c = (src / "matroska-demux.c").read_text()
c = sub_once(c, "#include <string.h>\n", "#include <string.h>\n#include <stdio.h>\n#include <stdarg.h>\n",
             "includes")
c = sub_once(c, "/* Check and set Dolby Vision */\n#ifdef DOLBYHDR_SUPPORT\n",
             "#ifdef DOLBYHDR_SUPPORT\n" + log + "#endif\n\n" + conv +
             "\n/* Check and set Dolby Vision */\n#ifdef DOLBYHDR_SUPPORT\n", "converter block")

old_p7 = '''    if (demux->dv_profile == 7) {
      GST_DEBUG_OBJECT (demux,
          "Dolby Vision profile 7 is not supported, but can play as HDR10.");
      return TRUE;
    } else if'''
new_p7 = '''    if (demux->dv_profile == 7) {
#ifdef DOLBYHDR_P7_TO_P81
      /* UHD Blu-ray (BL compatibility 6), single track: convert every RPU to
       * profile 8.1 on the fly and signal the track as Dolby Vision 8. */
      if (demux->dv_bl_signal_comp_id == 6
          && !(demux->has_dolby_bl_cand && demux->has_dolby_el_cand)
          && gst_matroska_demux_setup_dovi_p7_to_p81 (demux, context)) {
        gst_caps_set_simple (context->caps, "dolby-vision", G_TYPE_BOOLEAN,
            TRUE, "dolby-vision-profile", G_TYPE_INT, 8, NULL);
        matroska_dv_log ("decision profile=7.%d support=%d: dolby-vision set, "
            "converting profile 7 to 8.1", demux->dv_bl_signal_comp_id,
            demux->dolby_vision_support);
        return TRUE;
      }
      matroska_dv_log ("decision profile=7.%d: profile 7 is played as HDR10",
          demux->dv_bl_signal_comp_id);
#endif
      GST_DEBUG_OBJECT (demux,
          "Dolby Vision profile 7 is not supported, but can play as HDR10.");
      return TRUE;
    } else if'''
c = sub_once(c, old_p7, new_p7, "profile 7 branch")

old_set = '''    /* Set as Dolby Vision */
    GST_DEBUG_OBJECT (demux,'''
new_set = '''    /* Set as Dolby Vision */
#ifdef DOLBYHDR_P7_TO_P81
    matroska_dv_log ("decision profile=%d.%d support=%d: dolby-vision set "
        "(native)", demux->dv_profile, demux->dv_bl_signal_comp_id,
        demux->dolby_vision_support);
#endif
    GST_DEBUG_OBJECT (demux,'''
c = sub_once(c, old_set, new_set, "native DV log")
(src / "matroska-demux.c").write_text(c)
print("ok")
