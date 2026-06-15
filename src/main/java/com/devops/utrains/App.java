package com.devops.utrains;

public class App {

    public String greet(String name) {
        return "Hello here l.gb, " + name + "!";
    }

    public static void main(String[] args) {
        System.out.println(new App().greet("DevOps"));
    }
}
