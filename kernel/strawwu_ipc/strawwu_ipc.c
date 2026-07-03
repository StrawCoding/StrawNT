// SPDX-License-Identifier: GPL-2.0
/*
 * strawwu_ipc — StrawWU kernel↔userspace IPC stub (Phase 2).
 * Provides a misc char device for IOCTL probe responses; not a Windows driver.
 */
#include <linux/module.h>
#include <linux/miscdevice.h>
#include <linux/fs.h>
#include <linux/uaccess.h>

#define STRAWWU_IPC_NAME "strawwu_ipc"
#define STRAWWU_IPC_IOCTL_MAGIC 0x53

static long strawwu_ipc_ioctl(struct file *file, unsigned int cmd, unsigned long arg)
{
	/* Phase 2 stub: acknowledge probes; real dispatch comes in Phase 6. */
	switch (cmd) {
	default:
		return 0;
	}
}

static const struct file_operations strawwu_ipc_fops = {
	.owner = THIS_MODULE,
	.unlocked_ioctl = strawwu_ipc_ioctl,
	.compat_ioctl = strawwu_ipc_ioctl,
};

static struct miscdevice strawwu_ipc_dev = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = STRAWWU_IPC_NAME,
	.fops = &strawwu_ipc_fops,
};

static int __init strawwu_ipc_init(void)
{
	int ret;

	ret = misc_register(&strawwu_ipc_dev);
	if (ret)
		pr_err("strawwu_ipc: misc_register failed: %d\n", ret);
	else
		pr_info("strawwu_ipc: registered /dev/%s\n", STRAWWU_IPC_NAME);
	return ret;
}

static void __exit strawwu_ipc_exit(void)
{
	misc_deregister(&strawwu_ipc_dev);
	pr_info("strawwu_ipc: unregistered\n");
}

module_init(strawwu_ipc_init);
module_exit(strawwu_ipc_exit);

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("StrawWU kernel-userspace IPC stub device");
MODULE_AUTHOR("StrawWU Project");
