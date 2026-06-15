package com.devops.utrains;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class AppTest {

    @Test
    void greetIncludesName() {
        App app = new App();
        assertTrue(app.greet("DevOps").contains("DevOps"));
    }
}
