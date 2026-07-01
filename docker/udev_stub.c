/* udev_stub.c — LD_PRELOAD shim for running Vivado under emulation.
 *
 * The Xilinx FlexLM license manager (libXil_lmgr11.so) calls
 * udev_enumerate_scan_devices() to look for USB license dongles. Under
 * QEMU/Apple-Virtualization emulation that scan corrupts libudev's heap and
 * glibc aborts with "realloc(): invalid pointer", killing Vivado before it
 * can even read the .tcl.
 *
 * We have no dongle — the license is node-locked to the (MAC-derived) host
 * ID, which FlexLM reads via a separate code path. So we override the scan
 * entry points to no-ops. The enumerate object stays empty, the dongle loop
 * iterates nothing, and checkout proceeds on the file + host-ID license.
 *
 * Build (x86-64 ELF, inside an amd64 container):
 *   gcc -shared -fPIC -o docker/udev_stub.so docker/udev_stub.c
 * Use:
 *   -e LD_PRELOAD=/work/docker/udev_stub.so
 */
int udev_enumerate_scan_devices(void *enumerate)    { (void)enumerate; return 0; }
int udev_enumerate_scan_subsystems(void *enumerate) { (void)enumerate; return 0; }
