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
#include <signal.h>

static void check(int ret, const char *op) {
 if (ret < 0) { perror(op); exit(1); }
}
static void setreg(int vcpu, uint64_t id, uint64_t value) {
 struct kvm_one_reg r={.id=id,.addr=(uintptr_t)&value};
 check(ioctl(vcpu,KVM_SET_ONE_REG,&r),"KVM_SET_ONE_REG");
}
#define CORE_REG(member) (KVM_REG_ARM64|KVM_REG_SIZE_U64|KVM_REG_ARM_CORE|\
 (offsetof(struct kvm_regs,member)/sizeof(uint32_t)))
int main(int argc,char **argv) {
 int cpu=argc>1?atoi(argv[1]):-1;
 if (cpu>=0) { cpu_set_t mask;CPU_ZERO(&mask);CPU_SET(cpu,&mask);check(sched_setaffinity(0,sizeof(mask),&mask),"affinity"); }
 int hold=argc>2&&!strcmp(argv[2],"hold");
 alarm(hold?45:15);
 setbuf(stdout,NULL);
 uint64_t host_hz;
 __asm__ volatile("mrs %0, cntfrq_el0":"=r"(host_hz));
 printf("Host CNTFRQ=%llu Hz\n",(unsigned long long)host_hz);
 int kvm=open("/dev/kvm",O_RDWR|O_CLOEXEC);check(kvm,"open /dev/kvm");
 int api=ioctl(kvm,KVM_GET_API_VERSION,0);check(api,"KVM_GET_API_VERSION");
 if(api!=12){fprintf(stderr,"API=%d\n",api);return 1;}
 printf("KVM API=12 cpu=%d\n",sched_getcpu());
 int vm=ioctl(kvm,KVM_CREATE_VM,0);check(vm,"KVM_CREATE_VM");
 struct kvm_vcpu_init init={0};
 check(ioctl(vm,KVM_ARM_PREFERRED_TARGET,&init),"KVM_ARM_PREFERRED_TARGET");
 printf("VM created, target=%u\n",init.target);
 void *mem=mmap(NULL,65536,PROT_READ|PROT_WRITE,MAP_SHARED|MAP_ANONYMOUS,-1,0);
 if(mem==MAP_FAILED){perror("guest mmap");return 1;}
 // mov x0,#42; mov x1,#0x100000; str x0,[x1]; b back to mov.
 const uint32_t code[]={0xd2800540,0xd2a00201,0xf9000020,0x17fffffd};
 memcpy(mem,code,sizeof(code));
 struct kvm_userspace_memory_region region={.slot=0,.guest_phys_addr=0x400000,
  .memory_size=65536,.userspace_addr=(uintptr_t)mem};
 check(ioctl(vm,KVM_SET_USER_MEMORY_REGION,&region),"KVM_SET_USER_MEMORY_REGION");
 int vcpu=ioctl(vm,KVM_CREATE_VCPU,0);check(vcpu,"KVM_CREATE_VCPU");
 check(ioctl(vcpu,KVM_ARM_VCPU_INIT,&init),"KVM_ARM_VCPU_INIT");
 setreg(vcpu,CORE_REG(regs.pc),0x400000);
 setreg(vcpu,CORE_REG(regs.pstate),0x3c5);
 int size=ioctl(kvm,KVM_GET_VCPU_MMAP_SIZE,0);check(size,"KVM_GET_VCPU_MMAP_SIZE");
 struct kvm_run *run=mmap(NULL,size,PROT_READ|PROT_WRITE,MAP_SHARED,vcpu,0);
 if(run==MAP_FAILED){perror("run mmap");return 1;}
 puts("Entering guest");
 int ret;do{ret=ioctl(vcpu,KVM_RUN,0);}while(ret<0&&errno==EINTR);
 check(ret,"KVM_RUN");
 uint64_t value=0;memcpy(&value,run->mmio.data,8);
 if(run->exit_reason!=KVM_EXIT_MMIO||!run->mmio.is_write||run->mmio.phys_addr!=0x100000||run->mmio.len!=8||value!=42){
  fprintf(stderr,"FAIL exit=%u addr=%llx write=%u len=%u value=%llu\n",run->exit_reason,
   (unsigned long long)run->mmio.phys_addr,run->mmio.is_write,run->mmio.len,(unsigned long long)value);return 1;
 }
 puts("PASS: hardware KVM guest executed mov/mov/str; MMIO write 42 at 0x100000");
 if(hold) {
  const int cpus[]={0,1,2,3,4,5,6,7,0,4};
  for(unsigned i=0;i<sizeof(cpus)/sizeof(cpus[0]);i++) {
   // Keep this VM alive over idle/CPU PM, then migrate the same vCPU.
   sleep(2);
   cpu_set_t mask;CPU_ZERO(&mask);CPU_SET(cpus[i],&mask);
   check(sched_setaffinity(0,sizeof(mask),&mask),"hold affinity");
   do{ret=ioctl(vcpu,KVM_RUN,0);}while(ret<0&&errno==EINTR);
   check(ret,"KVM_RUN after idle/migration");
   memcpy(&value,run->mmio.data,8);
   if(run->exit_reason!=KVM_EXIT_MMIO||!run->mmio.is_write||run->mmio.phys_addr!=0x100000||value!=42) {
    fprintf(stderr,"FAIL held VM cpu=%d exit=%u value=%llu\n",cpus[i],run->exit_reason,(unsigned long long)value);return 1;
   }
   printf("PASS: same vCPU after idle on CPU %d\n",cpus[i]);
  }
 }
 munmap(run,size);close(vcpu);close(vm);close(kvm);munmap(mem,65536);
 return 0;
}
