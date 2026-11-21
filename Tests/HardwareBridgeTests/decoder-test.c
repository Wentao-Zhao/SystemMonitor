#include "HardwareBridge.h"
#include <math.h>
#include <stdio.h>
#include <string.h>
#define FOUR(a,b,c,d) ((uint32_t)(a)<<24|(uint32_t)(b)<<16|(uint32_t)(c)<<8|(uint32_t)(d))
static int check(int ok,const char *label){if(!ok)fprintf(stderr,"FAIL %s\n",label);return !ok;}
int main(void){int failures=0;float f=63.25f;uint8_t bytes[4];memcpy(bytes,&f,4);
failures+=check(HBDecodeSMCValue(FOUR('f','l','t',' '),bytes,4)==63.25,"SMC native float temperature");
uint8_t fixed[]={0x1f,0x40};failures+=check(HBDecodeSMCValue(FOUR('f','p','e','2'),fixed,2)==2000,"SMC unsigned fixed fan RPM");
uint8_t signedFixed[]={0xff,0x80};failures+=check(HBDecodeSMCValue(FOUR('s','p','7','8'),signedFixed,2)==-0.5,"SMC signed temperature");
uint8_t fanCount[]={2};failures+=check(HBDecodeSMCValue(FOUR('u','i','8',' '),fanCount,1)==2,"SMC unsigned count");
failures+=check(isnan(HBDecodeSMCValue(0,bytes,4)),"unsupported type remains unavailable");
failures+=check(isnan(HBDecodeSMCValue(FOUR('f','l','t',' '),bytes,2)),"short data rejected");
printf("decoder failures: %d\n",failures);return failures?1:0;}
