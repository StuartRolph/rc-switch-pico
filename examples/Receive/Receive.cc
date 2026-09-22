#include <iostream>
#include "pico/stdlib.h"
#include "../../radio-switch.h"

/*
Simple example of recieving radio remote signals.
This will help you to tell what your remote is sending out 
so you can recreate it :) 
*/
int main() {
    stdio_init_all();
    const uint RADIO_RECEIVER_PIN = 17;
    gpio_init(RADIO_RECEIVER_PIN);
    
    RCSwitch rcSwitch = RCSwitch();
    rcSwitch.enableReceive(RADIO_RECEIVER_PIN);

    // USB CDC discards output while no host is attached, so the banner below is
    // repeated while idle: the monitor can then be opened at any time and see it.
    // (0 means "print on the first pass through the loop".)
    absolute_time_t next_banner = make_timeout_time_ms(0);

    while (true) {
        if (time_reached(next_banner)) {
            std::cout << "receive: up, listening on GPIO " << RADIO_RECEIVER_PIN << std::endl;
            next_banner = make_timeout_time_ms(30000);
        }

        if (rcSwitch.available()) {
            std::cout << "VALUE RECEIVED: " << rcSwitch.getReceivedValue() << std::endl;
            std::cout << "PROTOCOL RECEIVED: " << rcSwitch.getReceivedProtocol() << std::endl;
            std::cout << "BIT LENGTH RECEIVED: " << rcSwitch.getReceivedBitlength() << std::endl;
            std::cout << "PULSELENGTH RECEIVED: " << rcSwitch.getReceivedDelay() << std::endl << std::endl;
            rcSwitch.resetAvailable();
            
            sleep_ms(100);
        }
    }

    return 0;
}