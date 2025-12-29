package com.example.demodebug;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloController {

  @GetMapping("/hello")
  public String hello(@RequestParam(defaultValue = "bhai") String name) {
    String msg = "Hello " + name;
    // breakpoint iske updar, neeche lagao
    return msg;
  }
}
