#define _GNU_SOURCE
#include <stdio.h>
#include <unistd.h>
#include <sys/utsname.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/socket.h>
#include <sys/ipc.h>
#include <sys/shm.h>
#include <arpa/inet.h>
#include <sched.h>
#include <signal.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>

static void die(const char *s){perror(s);exit(1);}
static long number(const char *path){FILE *f=fopen(path,"r");if(!f)return -1;long n=-1;if(fscanf(f,"%ld",&n)!=1)n=-1;fclose(f);return n;}
static long limit(const char *controller,const char *file){
 char path[1400];snprintf(path,sizeof(path),"/sys/fs/cgroup/%s/%s",controller,file);
 long n=number(path);if(n>=0)return n;
 FILE *f=fopen("/proc/self/cgroup","r");if(!f)die("cgroup membership");char line[1200];
 while(fgets(line,sizeof(line),f)){
  char *first=strchr(line,':');if(!first)continue;char *second=strchr(first+1,':');if(!second)continue;*second=0;
  int match=0;for(char *token=strtok(first+1,",");token;token=strtok(NULL,","))if(!strcmp(token,controller))match=1;
  if(!match)continue;
  char *group=second+1;group[strcspn(group,"\n")]=0;
  snprintf(path,sizeof(path),"/sys/fs/cgroup/%s%s/%s",controller,group,file);n=number(path);break;
 }
 fclose(f);return n;
}
static int echo_server(void){
 alarm(45);int s=socket(AF_INET,SOCK_DGRAM,0);if(s<0)die("socket");
 struct sockaddr_in a={.sin_family=AF_INET,.sin_port=htons(23142),.sin_addr.s_addr=htonl(INADDR_ANY)};
 if(bind(s,(void*)&a,sizeof(a)))die("bind");
 puts("READY UDP bridge echo");fflush(stdout);
 char b[128];socklen_t len=sizeof(a);ssize_t n=recvfrom(s,b,sizeof(b),0,(void*)&a,&len);if(n<0)die("recvfrom");
 if(sendto(s,b,n,0,(void*)&a,len)!=n)die("sendto");
 close(s);return 0;
}
int main(int argc,char **argv){
 setbuf(stdout,NULL);if(argc==2&&!strcmp(argv[1],"--server"))return echo_server();alarm(45);
 struct utsname u;if(uname(&u))die("uname");printf("Kernel: %s\n",u.release);printf("PID=%d UID=%d\n",getpid(),getuid());if(getpid()!=1)return 2;
 FILE*f=fopen("/proc/self/status","r");if(!f)die("status");char line[512];int sec=0;while(fgets(line,sizeof(line),f))if(!strncmp(line,"Seccomp:",8)){printf("%s",line);sec=atoi(line+8);}fclose(f);if(sec!=2)return 4;
 int out=open("/container-write",O_CREAT|O_WRONLY,0600);if(out<0)die("writable rootfs");if(write(out,"Docker on A51\n",14)!=14)die("write");close(out);
 int shmid=shmget(IPC_PRIVATE,4096,IPC_CREAT|0600);if(shmid<0)die("SYSV shmget");char *shared=shmat(shmid,NULL,0);if(shared==(void*)-1)die("shmat");strcpy(shared,"native IPC");if(shmdt(shared)||shmctl(shmid,IPC_RMID,NULL))die("shm cleanup");puts("PASS native SYSVIPC shared memory");
 if(argc>1){
  long mem=limit("memory","memory.limit_in_bytes"),pids=limit("pids","pids.max"),quota=limit("cpu","cpu.cfs_quota_us"),period=limit("cpu","cpu.cfs_period_us");
  long memsw=limit("memory","memory.memsw.limit_in_bytes");
  printf("cgroup memory=%ld memory_swap=%ld pids=%ld cpu_quota=%ld cpu_period=%ld\n",mem,memsw,pids,quota,period);
  if(mem!=67108864||memsw!=67108864||pids!=32||quota!=50000||period!=100000)return 7;
  cpu_set_t cpus;CPU_ZERO(&cpus);if(sched_getaffinity(0,sizeof(cpus),&cpus))die("CPU affinity");if(CPU_COUNT(&cpus)!=2||!CPU_ISSET(0,&cpus)||!CPU_ISSET(1,&cpus))return 8;puts("PASS cpuset CPU affinity and CPU quota");
  int to[2];if(pipe(to))die("pipe");pid_t children[40];int count=0;errno=0;
  for(;count<40;count++){pid_t child=fork();if(child<0)break;if(!child){close(to[1]);char b;ssize_t n=read(to[0],&b,1);_exit(n>=0?0:1);}children[count]=child;}
  int exhausted=errno==EAGAIN&&count==31;close(to[1]);close(to[0]);for(int i=0;i<count;i++)waitpid(children[i],NULL,0);
  if(!exhausted){fprintf(stderr,"Unexpected pids limit count=%d\n",count);return 9;}puts("PASS Docker pids limit enforced at 32 tasks");
  pid_t child=fork();if(child<0)die("memory test fork");if(!child){volatile char *p=malloc(96*1024*1024);if(!p){perror("over-limit malloc");_exit(11);}for(size_t i=0;i<96*1024*1024;i+=4096)p[i]=1;_exit(12);}int status;if(waitpid(child,&status,0)<0)die("wait OOM child");printf("memory child wait status=%d max_usage=%ld failcnt=%ld\n",status,limit("memory","memory.max_usage_in_bytes"),limit("memory","memory.failcnt"));if(!WIFSIGNALED(status)||WTERMSIG(status)!=SIGKILL)return 10;puts("PASS Docker memory cgroup killed only the over-limit child");
 }
 if(argc==3){int s=socket(AF_INET,SOCK_DGRAM,0);if(s<0)die("UDP socket");struct timeval tv={.tv_sec=5};setsockopt(s,SOL_SOCKET,SO_RCVTIMEO,&tv,sizeof(tv));struct sockaddr_in a={.sin_family=AF_INET,.sin_port=htons(23142)};if(inet_pton(AF_INET,argv[2],&a.sin_addr)!=1)return 13;char token[]="A51 native bridge traffic";if(sendto(s,token,sizeof(token),0,(void*)&a,sizeof(a))!=(ssize_t)sizeof(token))die("UDP send");char b[128];ssize_t n=recv(s,b,sizeof(b),0);if(n!=(ssize_t)sizeof(token)||memcmp(token,b,sizeof(token)))return 14;close(s);puts("PASS UDP round trip through Docker veth and bridge");}
 puts("PASS native Docker container, PID namespace, default seccomp, writable rootfs");return 0;
}
