/*
 *  Copyright 2016 Frank Hunleth
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#ifndef starter_port_COMM_H
#define starter_port_COMM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

enum starter_port_parity
{
    starter_port_PARITY_NONE = 0,
    starter_port_PARITY_EVEN,
    starter_port_PARITY_ODD,
    starter_port_PARITY_SPACE,
    starter_port_PARITY_MARK,
    starter_port_PARITY_IGNORE
};

enum starter_port_flow_control
{
    starter_port_FLOWCONTROL_NONE = 0,
    starter_port_FLOWCONTROL_HARDWARE,
    starter_port_FLOWCONTROL_SOFTWARE
};

enum starter_port_direction
{
    starter_port_DIRECTION_RECEIVE = 0,
    starter_port_DIRECTION_TRANSMIT,
    starter_port_DIRECTION_BOTH
};

struct starter_port_config
{
    bool active;
    int speed;     // 9600, 115200, etc.
    int data_bits; // 5, 6, 7, 8
    int stop_bits; // 1 or 2
    enum starter_port_parity parity;
    enum starter_port_flow_control flow_control;
};

struct starter_port_signals
{
    bool dsr;
    bool dtr;
    bool rts;
    bool st;
    bool sr;
    bool cts;
    bool cd;
    bool rng;
};

struct starter_port;

void starter_port_default_config(struct starter_port_config *config);

const char *starter_port_last_error();

typedef void (*starter_port_write_completed_callback)(int rc, const uint8_t *data);
typedef void (*starter_port_read_completed_callback)(int rc, const uint8_t *data, size_t len);
typedef void (*starter_port_notify_read)(int error_reason, const uint8_t *data, size_t len);

/**
 * @brief Initialize the starter_port data
 *
 * @param pport a starter_port struct is allocated and returned on success
 * @param write_completed a callback for completed writes
 * @return 0 on success, <0 on error
 */
int starter_port_init(struct starter_port **pport,
                      starter_port_write_completed_callback write_completed,
                      starter_port_read_completed_callback read_completed,
                      starter_port_notify_read notify_read);

/**
 * @brief Return true (1) if port is open
 *
 * @param port the starter_port struct
 * @return 0 if closed, 1 if open
 */
int starter_port_is_open(struct starter_port *port);

/**
 * @brief Open the specified starter_port port
 *
 * @param port the starter_port struct
 * @param name  the name of the port to open
 * @param config the initial configuration
 * @return 0 on success, <0 on error
 */
int starter_port_open(struct starter_port *port, const char *name, const struct starter_port_config *config);

/**
 * @brief Close and free up the resources for a starter_port
 * @param port the starter_port struct
 * @return 0 on success
 */
int starter_port_close(struct starter_port *port);

/**
 * @brief Write data to the starter_port
 *
 * An attempt can be made to send the data synchronously, but many
 * transfers complete asynchrously, so the data buffer shouldn't be
 * freed until the write_completed() callback is invoked.
 *
 * Only one write may be pending at a time.
 *
 * @param port the starter_port struct
 * @param data the bytes to write
 * @param len how many
 * @param timeout the max number of milliseconds to allow (-1 = forever)
 * @return the write_completed callback is always invoked with the result
 */
void starter_port_write(struct starter_port *port, const uint8_t *data, size_t len, int timeout);

/**
 * @brief Read data from the starter_port
 *
 * This function initiates a read from the starter_port. The results of the read
 * are reported by the read_completed() callback. If nothing is immediately
 * available and the timeout allows for it, the operation occurs asynchronously.
 *
 * Only one read may be pending at a time.
 *
 * @param port the starter_port struct
 * @param timeout wait up to this long for something to be received
 *                -1 means wait forever
 * @return the read_completed callback is always invoked
 */
void starter_port_read(struct starter_port *port, int timeout);

/**
 * @brief Update the starter_port's configuration
 *
 * @param port the starter_port struct
 * @param config the new configuration
 * @return <0 on error
 */
int starter_port_configure(struct starter_port *port, const struct starter_port_config *config);

/**
 * @brief Block until all data is written out the port
 *
 * @param port the starter_port struct
 * @return 0 on success
 */
int starter_port_drain(struct starter_port *port);

/**
 * @brief Flush the receive and/or transmit queues
 *
 * @param port the starter_port struct
 * @param direction which direction
 * @return 0 on success
 */
int starter_port_flush(struct starter_port *port, enum starter_port_direction direction);

/**
 * @brief Flush the tx and rx queues
 *
 * @param port the starter_port struct
 * @return 0 on success
 */
int starter_port_flush_all(struct starter_port *port);

/**
 * @brief Set or clear the Request To Send signal
 *
 * @param port the starter_port struct
 * @param val true or false
 * @return 0 on success
 */
int starter_port_set_rts(struct starter_port *port, bool val);

/**
 * @brief Set or clear the Data Terminal Ready signal
 *
 * @param port the starter_port struct
 * @param val true or false
 * @return 0 on success
 */
int starter_port_set_dtr(struct starter_port *port, bool val);

/**
 * @brief Set or clear the break signal
 *
 * @param port the starter_port struct
 * @param val true or false
 * @return 0 on success
 */
int starter_port_set_break(struct starter_port *port, bool val);

/**
 * @brief Read the state of all starter_port signals
 *
 * @param port the starter_port struct
 * @param sig the state is returned here
 * @return 0 on success
 */
int starter_port_get_signals(struct starter_port *port, struct starter_port_signals *sig);

#if defined(__linux__) || defined(__APPLE__)
struct pollfd;

/**
 * @brief Update fdset with desired events
 *
 * @param port the starter_port struct
 * @param fdset an open fdset slot
 * @param timeout milliseconds to poll
 *
 * @return the number of events added
 */
int starter_port_add_poll_events(struct starter_port *port, struct pollfd *fdset, int *timeout);

/**
 * @brief Process events
 *
 * @param port the starter_port struct
 * @param fdset the returned fdset from poll()
 */
void starter_port_process(struct starter_port *port, const struct pollfd *fdset);
#elif defined(__WIN32__)
#include <windows.h>

int starter_port_add_wfmo_handles(struct starter_port *port, HANDLE *handles, DWORD *timeout);

void starter_port_process_handle(struct starter_port *port, HANDLE *event);
void starter_port_process_timeout(struct starter_port *port);

#else
#error Unsupported platform
#endif

#endif // starter_port_COMM_H
