package com.example.demo;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloController {

    private static final Logger logger =
            LoggerFactory.getLogger(HelloController.class);

    @GetMapping("/hello")
    public String hello() {
        logger.info("Hello endpoint was called");
        return "Hello! Jenkins automatically builds my Java Microservice!";
    }

    @GetMapping("/health")
    public String health() {
        logger.info("Health endpoint was called");
        return "Java Microservice is UP";
    }
}
