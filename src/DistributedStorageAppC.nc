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
	components new AMSenderC(AM_BLINKTORADIO);		// Sending packets
	components new AMReceiverC(AM_BLINKTORADIO);	// Reading packet content

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
	App.Packet->AMSenderC;
	App.AMSend->AMSenderC;
	App.AMControl->ActiveMessageC;
}