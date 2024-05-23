#!/system/bin/sh

set -e

LIBPATH="$MODPATH/util/lib/${ARCH}"
export PATH="${PATH}:$MODPATH/util/bin/${ARCH}"
TMPPATH="$MODPATH/tmp"
chmod -R 755 "$MODPATH/util/"
mkdir "$TMPPATH"

cp /system/framework/services.jar "$TMPPATH"

ui_print "* Extracting services"
unzip -q "$TMPPATH/services.jar" -d "$TMPPATH/services"
for C in "$TMPPATH"/services/classes*; do
    if [ "$C" = "$TMPPATH/services/classes*" ]; then
        ls -l "$TMPPATH/services/"
        abort "classes glob fail"
    fi
    O="${C##*/}"
    O="${O%.*}"
    ui_print "* Disassembling $O"
    ANDROID_DATA="$TMPPATH" CLASSPATH="$MODPATH/util/baksmali.jar" app_process "$MODPATH" \
        com.android.tools.smali.baksmali.Main d "$C" -o "$TMPPATH/services-da/$O"
done

ui_print "* Patching isSecureLocked"
TARGET=$(grep -rn -x '.method .*isSecureLocked()Z' "$TMPPATH/services-da")
[ -z "$TARGET" ] && abort "Method not found"
TARGET_SMALI="${TARGET%%:*}"
TARGET_CLASS="${TARGET_SMALI#"$TMPPATH/services-da/"}"
TARGET_CLASS="${TARGET_CLASS%%/*}"
TMP_TARGET_CLASS="$TMPPATH/${TARGET_SMALI##*/}"
awk '
BEGIN {
    in_method = 0
}
/\.method .*isSecureLocked\(\)Z/ {
    in_method = 1
    print
    print "    .registers 1"
    print "    const/4 v0, 0x0"
    print "    return v0"
    next
}
/\.end method/ && in_method {
    in_method = 0
    print
    next
}
{
    if (!in_method) print
}
' "$TARGET_SMALI" >"$TMP_TARGET_CLASS"
mv -f "$TMP_TARGET_CLASS" "$TARGET_SMALI"

if [ "$API" -ge 34 ]; then
    ui_print "* Patching notifyScreenshotListeners (SDK level >= 34)"
    TARGET=$(grep -rn -x '.method .*notifyScreenshotListeners(I)Ljava/util/List;' "$TMPPATH/services-da")
    [ -z "$TARGET" ] && abort "Method not found"
    TARGET_SMALI="${TARGET%%:*}"
    TARGET_CLASS="${TARGET_SMALI#"$TMPPATH/services-da/"}"
    TARGET_CLASS="${TARGET_CLASS%%/*}"
    TMP_TARGET_CLASS="$TMPPATH/${TARGET_SMALI##*/}"
    awk '
BEGIN {
    in_method = 0
}
/\.method .*notifyScreenshotListeners\(I\)Ljava\/util\/List;/ {
    in_method = 1
    print
    print "    .registers 2"
    print "    .annotation system Ldalvik/annotation/Signature;"
    print "        value = {"
    print "            \"(I)\","
    print "            \"Ljava/util/List<\","
    print "            \"Landroid/content/ComponentName;\","
    print "            \">;\""
    print "        }"
    print "    .end annotation"
    print "    invoke-static {}, Ljava/util/Collections;->emptyList()Ljava/util/List;"
    print "    move-result-object p1"
    print "    return-object p1"
    next
}
/\.end method/ && in_method {
    in_method = 0
    print
    next
}
{
    if (!in_method) print
}
' "$TARGET_SMALI" >"$TMP_TARGET_CLASS"
    mv -f "$TMP_TARGET_CLASS" "$TARGET_SMALI"
fi

ui_print "* Re-assembling"
A=$(getprop ro.build.version.sdk)
ANDROID_DATA="$TMPPATH" CLASSPATH="$MODPATH/util/smali.jar" app_process "$MODPATH" \
    com.android.tools.smali.smali.Main a -a "$A" "$TMPPATH/services-da/$TARGET_CLASS" \
    -o "$TMPPATH/services/$TARGET_CLASS.dex"

ui_print "* Zipping"
cd "$TMPPATH/services/" || abort "unreachable1"
LD_LIBRARY_PATH=$LIBPATH zip -q -0 -r "$TMPPATH/services-patched.zip" ./
cd "$MODPATH" || abort "unreachable2"

ui_print "* Zip aligning"
LD_LIBRARY_PATH=$LIBPATH zipalign -p -z 4 "$TMPPATH/services-patched.zip" "$MODPATH/system/framework/services.jar"
set_perm "$MODPATH/system/framework/services.jar" 0 0 644 u:object_r:system_file:s0

ui_print "* Cleanup"
if [ "$ARCH" = x64 ]; then INS_SET=x86_64; else INS_SET=$ARCH; fi
rm -r "$TMPPATH" "$MODPATH/util"
rm "/data/dalvik-cache/$INS_SET/system@framework@services.jar@classes.dex" 2>/dev/null || :

ui_print "* Optimizing"
mkdir "$MODPATH/system/framework/oat/$INS_SET"
dex2oat --dex-file="$MODPATH/system/framework/services.jar" --instruction-set="$INS_SET" \
    --oat-file="$MODPATH/system/framework/oat/$INS_SET/services.odex"
set_perm "$MODPATH/system/framework/oat/$INS_SET/services.odex" 0 0 644 u:object_r:system_file:s0
set_perm "$MODPATH/system/framework/oat/$INS_SET/services.vdex" 0 0 644 u:object_r:system_file:s0

ui_print ""
ui_print "  by github.com/j-hc"

set +e
