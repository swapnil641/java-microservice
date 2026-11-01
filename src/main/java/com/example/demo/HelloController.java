package com.example.demo;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloController {

    @GetMapping("/hello")
    public String hello() {
        return "Hello! My first Java Microservice is running.";
    }

    @GetMapping("/health")
    public String health() {
        return "Java Microservice is UP";
    }
}