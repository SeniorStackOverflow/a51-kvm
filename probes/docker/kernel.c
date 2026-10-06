#define _GNU_SOURCE
#include <sched.h>
#include <sys/mount.h>
#include <sys/prctl.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <stddef.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>

static void fail(const char *s){perror(s);exit(1);}
static void ck(int r,const char *s){if(r<0)fail(s);}
static void put(const char *p,const char *s){int f=open(p,O_WRONLY);ck(f,p);size_t n=strlen(s);if(write(f,s,n)!=(ssize_t)n)fail("write");close(f);}
static void mkdir_ok(const char*p){if(mkdir(p,0700)<0&&errno!=EEXIST)fail(p);}
static void ns(int flag,const char*name){pid_t p=fork();ck(p,"fork");if(!p){ck(unshare(flag),name);_exit(0);}int st;ck(waitpid(p,&st,0),"waitpid");if(!WIFEXITED(st)||WEXITSTATUS(st)){fprintf(stderr,"FAIL namespace %s\n",name);exit(1);}printf("PASS namespace %s\n",name);}
int main(int argc,char**argv){
 if(argc!=2&&!(argc==3&&!strcmp(argv[2],"f2fs"))){fprintf(stderr,"usage: probe private-test-directory [f2fs]\n");return 2;}
 alarm(40);setbuf(stdout,NULL);
 ns(CLONE_NEWUTS,"UTS");ns(CLONE_NEWIPC,"IPC");ns(CLONE_NEWPID,"PID");ns(CLONE_NEWNET,"NET");ns(CLONE_NEWUSER,"USER");
 ck(unshare(CLONE_NEWNS),"mount namespace");ck(mount(NULL,"/",NULL,MS_REC|MS_PRIVATE,NULL),"private mounts");
 printf("PASS namespace MOUNT\n");
 const char*base=argv[1];mkdir_ok(base);ck(chdir(base),"chdir");
 mkdir_ok("overlay");if(argc==2)ck(mount("tmpfs","overlay","tmpfs",0,"size=16m"),"overlay backing tmpfs");
 mkdir_ok("overlay/lower");mkdir_ok("overlay/upper");mkdir_ok("overlay/work");mkdir_ok("overlay/merged");
 int f=open("overlay/lower/file",O_CREAT|O_WRONLY,0600);ck(f,"lower file");ck(write(f,"lower",5),"lower write");close(f);
 char opts[1024];snprintf(opts,sizeof(opts),"lowerdir=%s/overlay/lower,upperdir=%s/overlay/upper,workdir=%s/overlay/work",base,base,base);
 ck(mount("overlay","overlay/merged","overlay",0,opts),"mount overlayfs");
 f=open("overlay/merged/file",O_RDWR);ck(f,"merged file");char b[8]={0};ck(read(f,b,5),"read lower");if(strcmp(b,"lower"))return 1;ck(lseek(f,0,SEEK_SET),"seek");ck(write(f,"upper",5),"copy up");close(f);
 f=open("overlay/upper/file",O_RDONLY);ck(f,"upper file");memset(b,0,sizeof(b));ck(read(f,b,5),"read upper");close(f);if(strcmp(b,"upper"))return 1;
 printf("PASS overlayfs mount/read/copy-up on %s\n",argc==2?"tmpfs":"data filesystem");ck(umount("overlay/merged"),"umount overlay");if(argc==2)ck(umount("overlay"),"umount tmpfs");
 const char*controllers[]={"devices","pids","blkio"};
 for(int i=0;i<3;i++){char dir[128];snprintf(dir,sizeof(dir),"cg-%s",controllers[i]);mkdir_ok(dir);ck(mount("cgroup",dir,"cgroup",0,controllers[i]),"mount cgroup controller");char g[256];snprintf(g,sizeof(g),"%s/probe",dir);mkdir_ok(g);
  char path[512];snprintf(path,sizeof(path),"%s/%s",g,i==0?"devices.list":i==1?"pids.max":"blkio.weight");f=open(path,O_RDONLY);ck(f,"controller file");close(f);
  if(i==1){snprintf(path,sizeof(path),"%s/pids.max",g);put(path,"1\n");int to[2],from[2];ck(pipe(to),"pipe");ck(pipe(from),"pipe");pid_t p=fork();ck(p,"fork child");if(!p){char c;close(to[1]);close(from[0]);ck(read(to[0],&c,1),"wait move");errno=0;pid_t next=fork();c=next<0&&errno==EAGAIN?'Y':'N';if(next==0)_exit(0);if(next>0)waitpid(next,NULL,0);ck(write(from[1],&c,1),"report");_exit(c=='Y'?0:1);}close(to[0]);close(from[1]);char id[64];snprintf(id,sizeof(id),"%d\n",p);snprintf(path,sizeof(path),"%s/cgroup.procs",g);put(path,id);ck(write(to[1],"X",1),"release child");char c;ck(read(from[0],&c,1),"child result");int st;ck(waitpid(p,&st,0),"wait child");close(to[1]);close(from[0]);if(c!='Y'||st!=0)return 1;puts("PASS cgroup pids.max enforces fork limit");}
  if(i==2){snprintf(path,sizeof(path),"%s/blkio.weight",g);put(path,"500\n");}
  ck(rmdir(g),"remove test cgroup");ck(umount(dir),"umount cgroup");printf("PASS cgroup %s\n",controllers[i]);
 }
 struct sock_filter filter[]={BPF_STMT(BPF_LD|BPF_W|BPF_ABS,offsetof(struct seccomp_data,nr)),BPF_JUMP(BPF_JMP|BPF_JEQ|BPF_K,__NR_getppid,0,1),BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ERRNO|EPERM),BPF_STMT(BPF_RET|BPF_K,SECCOMP_RET_ALLOW)};
 struct sock_fprog prog={.len=sizeof(filter)/sizeof(filter[0]),.filter=filter};
 ck(prctl(PR_SET_NO_NEW_PRIVS,1,0,0,0),"no new privs");ck(prctl(PR_SET_SECCOMP,SECCOMP_MODE_FILTER,&prog),"seccomp filter");errno=0;if(syscall(__NR_getppid)!=-1||errno!=EPERM)return 1;if(syscall(__NR_getpid)<=0)return 1;
 puts("PASS seccomp filter denies getppid and allows getpid");puts("PASS all native Docker kernel primitives in this probe");return 0;
}
