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

#include <stdbool.h>
#include <stdint.h>

#include "erlcmd.h"
#include "starter_port_comm.h"
#include "starter_port_enum.h"
#include "util.h"

#ifndef __WIN32__
#include <string.h>
#include <unistd.h>
#endif

/*
 * These tests are only enabled when DEBUG is definied. They're sometimes
 * useful when debugging the C code so that Erlang and Elixir don't
 * complicate things.
 */
#ifdef DEBUG
static struct starter_port *starter_port = NULL;

static bool test_write_is_done = false;
static bool test_read_is_done = false;
static void test_write_completed(int rc, const uint8_t *data)
{
    (void)data;
    debug("test_write_completed: rc=%d", rc);
    if (rc < 0)
        errx(EXIT_FAILURE, "Error from starter_port_write: %s\n", starter_port_last_error());
    test_write_is_done = true;
}
static void test_read_completed(int rc, const uint8_t *data, size_t len)
{
    (void)data;
    debug("test_read_completed: rc=%d, %d bytes", rc, (int)len);
    if (rc < 0)
        errx(EXIT_FAILURE, "Error from starter_port_read: %s\n", starter_port_last_error());
    test_read_is_done = true;
}

static void test_wait_once(struct erlcmd *handler)
{
#ifdef __WIN32__
    HANDLE handles[3];
    DWORD timeout = INFINITE;
    handles[0] = erlcmd_wfmo_event(handler);
    int count = 1 + starter_port_add_wfmo_handles(starter_port, &handles[1], &timeout);
    debug("Calling WFMO...");
    DWORD result = WaitForMultipleObjects(count,
                                          handles,
                                          FALSE,
                                          timeout);
    debug("WFMO result=%d!!", (int)result);
    switch (result)
    {
    case WAIT_OBJECT_0 + 0:
        erlcmd_process(handler);
        break;
    case WAIT_OBJECT_0 + 1:
    case WAIT_OBJECT_0 + 2:
        starter_port_process_handle(starter_port, handles[result]);
        break;
    case WAIT_TIMEOUT:
        starter_port_process_timeout(starter_port);
        break;
    default:
        errx(EXIT_FAILURE, "Error from WFMO");
        break;
    }
#else
    (void)handler;
    usleep(1000);
    fprintf(stderr, "polling\n");
    starter_port_process(starter_port, NULL);
#endif
}

void test()
{
    struct erlcmd *handler = malloc(sizeof(struct erlcmd));
    erlcmd_init(handler, NULL, NULL);

    struct serial_info *port_list = find_serialports();
    if (!port_list)
    {
        fprintf(stderr, "No serial ports detected!\n");
        return;
    }
    fprintf(stderr, "Name: %s\n", port_list->name);
    fprintf(stderr, "Description: %s\n", port_list->description);
    fprintf(stderr, "Manufacturer: %s\n", port_list->manufacturer);
    fprintf(stderr, "Serial number: %s\n", port_list->serial_number);
    fprintf(stderr, "vid: 0x%04x\n", port_list->vid);
    fprintf(stderr, "pid: 0x%04x\n", port_list->pid);
    fprintf(stderr, "---\n");

    fprintf(stderr, "Calling open on %s...\n", port_list->name);
    struct starter_port_config config;
    starter_port_default_config(&config);
    config.active = false;

    starter_port_init(&starter_port, test_write_completed, test_read_completed, NULL);
    int rc = starter_port_open(starter_port, port_list->name, &config);
    if (rc < 0)
        errx(EXIT_FAILURE, "Error from starter_port_open: %s\n", starter_port_last_error());

    fprintf(stderr, "Calling write...\n");
    int big_buffer_size = 100; // This may take a while.
    uint8_t *big_buffer = malloc(big_buffer_size);
    memset(big_buffer, 'a', big_buffer_size);
    starter_port_write(starter_port, big_buffer, big_buffer_size, -1);

    while (!test_write_is_done)
        test_wait_once(handler);
    free(big_buffer);

    for (int i = 0; i < 10; i++)
    {
        test_read_is_done = false;
        fprintf(stderr, "Calling read (%d)...\n", i);
        starter_port_read(starter_port, 1000);
        while (!test_read_is_done)
            test_wait_once(handler);
        fprintf(stderr, "starter_port_read returned %d\n", rc);
    }

    fprintf(stderr, "Done!\n");
    starter_port_close(starter_port);
    serial_info_free_list(port_list);
}
#endif
