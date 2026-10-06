// The stream must not outlive Ordinary Notch after a crash or forced app restart.
#import <Foundation/Foundation.h>
#include <unistd.h>
static dispatch_source_t parentWatch;
__attribute__((constructor)) static void watchParent(void) {
    pid_t parent = getppid();
    parentWatch = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                        dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(parentWatch, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                              2 * NSEC_PER_SEC, NSEC_PER_SEC / 2);
    dispatch_source_set_event_handler(parentWatch, ^{ if (getppid() != parent) _exit(0); });
    dispatch_resume(parentWatch);
}
