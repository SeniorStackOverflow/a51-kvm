#define _GNU_SOURCE
#include <linux/kvm.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stddef.h>
#include <errno.h>

static void check(int r,const char *name) {if(r<0){perror(name);exit(1);}}
static void attr(int dev,uint32_t group,uint64_t field,uint64_t *value) {
 struct kvm_device_attr a={.group=group,.attr=field,.addr=(uintptr_t)value};
 check(ioctl(dev,KVM_SET_DEVICE_ATTR,&a),"VGIC KVM_SET_DEVICE_ATTR");
}
static void reg(int vcpu,uint64_t id,uint64_t value) {
 struct kvm_one_reg r={.id=id,.addr=(uintptr_t)&value};
 check(ioctl(vcpu,KVM_SET_ONE_REG,&r),"KVM_SET_ONE_REG");
}
#define CORE(member) (KVM_REG_ARM64|KVM_REG_SIZE_U64|KVM_REG_ARM_CORE|\
 (offsetof(struct kvm_regs,member)/sizeof(uint32_t)))
int main(int argc,char **argv) {
 int cpu=argc>1?atoi(argv[1]):0;cpu_set_t mask;CPU_ZERO(&mask);CPU_SET(cpu,&mask);
 check(sched_setaffinity(0,sizeof(mask),&mask),"affinity");
 setbuf(stdout,NULL);alarm(15);
 int kvm=open("/dev/kvm",O_RDWR|O_CLOEXEC);check(kvm,"open /dev/kvm");
 if(ioctl(kvm,KVM_GET_API_VERSION,0)!=12)return 1;
 int vm=ioctl(kvm,KVM_CREATE_VM,0);check(vm,"CREATE_VM");
 struct kvm_create_device create={.type=KVM_DEV_TYPE_ARM_VGIC_V2};
 check(ioctl(vm,KVM_CREATE_DEVICE,&create),"CREATE_VGIC_V2");
 uint64_t dist=0x08000000,cpuif=0x08010000;
 attr(create.fd,KVM_DEV_ARM_VGIC_GRP_ADDR,KVM_VGIC_V2_ADDR_TYPE_DIST,&dist);
 attr(create.fd,KVM_DEV_ARM_VGIC_GRP_ADDR,KVM_VGIC_V2_ADDR_TYPE_CPU,&cpuif);
 void *mem=mmap(NULL,65536,PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANONYMOUS,-1,0);
 if(mem==MAP_FAILED){perror("memory");return 1;}
 FILE *f=fopen(argc > 2 ? argv[2] : "/data/local/tmp/kvm-timer-guest.bin","rb");if(!f){perror("guest code");return 1;}
 size_t n=fread(mem,1,65536,f);fclose(f);if(n==0||n==65536)return 1;
 struct kvm_userspace_memory_region slot={.slot=0,.guest_phys_addr=0x400000,
  .memory_size=65536,.userspace_addr=(uintptr_t)mem};
 check(ioctl(vm,KVM_SET_USER_MEMORY_REGION,&slot),"SET_MEMORY");
 struct kvm_vcpu_init init={0};check(ioctl(vm,KVM_ARM_PREFERRED_TARGET,&init),"PREFERRED_TARGET");
 int vcpu=ioctl(vm,KVM_CREATE_VCPU,0);check(vcpu,"CREATE_VCPU");
 check(ioctl(vcpu,KVM_ARM_VCPU_INIT,&init),"VCPU_INIT");
 attr(create.fd,KVM_DEV_ARM_VGIC_GRP_CTRL,KVM_DEV_ARM_VGIC_CTRL_INIT,NULL);
 reg(vcpu,CORE(regs.pc),0x400000);reg(vcpu,CORE(regs.pstate),0x3c5);
 reg(vcpu,CORE(sp_el1),0x40f000);
 int size=ioctl(kvm,KVM_GET_VCPU_MMAP_SIZE,0);check(size,"VCPU_MMAP_SIZE");
 struct kvm_run *run=mmap(NULL,size,PROT_READ|PROT_WRITE,MAP_SHARED,vcpu,0);
 if(run==MAP_FAILED){perror("run mmap");return 1;}
 printf("Entering guest with VGICv2 and virtual timer on CPU %d\n",cpu);
 int ret;do{ret=ioctl(vcpu,KVM_RUN,0);}while(ret<0&&errno==EINTR);check(ret,"KVM_RUN timer");
 uint64_t irq=0;memcpy(&irq,run->mmio.data,8);
 if(run->exit_reason!=KVM_EXIT_MMIO||!run->mmio.is_write||run->mmio.phys_addr!=0x100000||run->mmio.len!=8||(irq&1023)!=27) {
  fprintf(stderr,"FAIL timer exit=%u addr=%llx irq=%llu\n",run->exit_reason,
    (unsigned long long)run->mmio.phys_addr,(unsigned long long)irq);return 1;
 }
 printf("PASS: guest virtual timer fired; VGICv2 delivered PPI27 to guest IRQ handler on CPU %d\n",cpu);
 munmap(run,size);close(vcpu);close(create.fd);close(vm);close(kvm);munmap(mem,65536);
 return 0;
}
