/*
  Copyright 1999 Kazuhiro HIWADA
  Copyright 2006 Suraj N. Kurapati
  See the file named LICENSE for details.
*/

#include "main.h"
#include "relay.h"
#include <stdlib.h>
#include <stdio.h>


// load the SWIG-generated Ruby interface to VPI
#include "swig_wrap.cin"


void main_init() {
  ruby_init();
  ruby_init_loadpath();

  // load the VPI interface for Ruby
    Init_vpi();
    rb_define_module_function(mVpi, "relay_verilog", main_relay_verilog, 0);
    rb_define_module_function(mVpi, "relay_ruby_reason", main_relay_ruby_reason, 0);

  // initialize the Ruby bench
    char* benchFile = getenv("RUBYVPI_BOOTSTRAP");

    if (benchFile != NULL) {
      ruby_script(benchFile);
      rb_load_file(benchFile);
    }
    else {
      common_printf("error: environment variable RUBY_VPI__RUBY_BENCH_FILE is uninitialized.");
      exit(EXIT_FAILURE);
    }

  // run the test bench
    ruby_run();

  ruby_finalize();
}

VALUE main_relay_verilog(VALUE arSelf) {
  relay_verilog();
  return arSelf;
}

VALUE main_relay_ruby_reason(VALUE arSelf) {
  return SWIG_NewPointerObj(vlog_relay_ruby_reason(), SWIGTYPE_p_t_cb_data, 0);
}
