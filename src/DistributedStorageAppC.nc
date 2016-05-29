#include <Timer.h>
#include "DistributedStorage.h"
#include "StorageVolumes.h"							// Here VOLUME_BLOCKDATA variables is defined. It is generated at compile time.
#include <UserButton.h>

configuration DistributedStorageAppC {
}
implementation {
	components MainC;
	components LedsC;
	components DistributedStorageC as App;
	components new TimerMilliC() as SyncTimer;
	components new TimerMilliC() as AckTimer;
	components new TimerMilliC() as SendTimer;

	components ActiveMessageC;
	components SerialActiveMessageC as AM;
	components new AMSenderC(AM_LOGDATAMSG);		// Sending packets
	components new AMReceiverC(AM_LOGDATAMSG);	// Reading packet content

	components new BlockStorageC(VOLUME_BLOCKDATA);
	
	components UserButtonC;
	
	App.BlockRead -> BlockStorageC;
  	App.BlockWrite -> BlockStorageC;
  	
  	App.Get -> UserButtonC;
  	App.Notify -> UserButtonC;
  	
	App.Boot->MainC;
	App.Leds->LedsC;
	App.SyncTimer->SyncTimer;
	App.AckTimer->AckTimer;
	App.SendTimer->SendTimer;

	App.Receive->AMReceiverC;

	App.SerialSend->AM.AMSend[AM_TEST_SERIAL_MSG];
	App.SerialReceive->AM.Receive[AM_TEST_SERIAL_MSG];
	App.SerialPacket -> AM;

	App.Packet->AMSenderC;
	App.AMSend->AMSenderC;
	App.AMControl->ActiveMessageC;
	App.SerialBlockRead-> BlockStorageC;
}
