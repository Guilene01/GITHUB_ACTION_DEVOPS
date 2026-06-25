package com.utrains.devops;

import static spark.Spark.*;

public class App {

    public String greet(String name) {
        return "Hello, " + name + "!";
    }

    public static void main(String[] args) {
        port(8080);

        get("/", (req, res) -> {
            res.type("text/html");
            return """
                <!DOCTYPE html>
                <html lang="en">
                <head>
                    <meta charset="UTF-8">
                    <meta name="viewport" content="width=device-width, initial-scale=1.0">
                    <title>Utrains DevOps App</title>
                    <style>
                        body {
                            margin: 0;
                            font-family: Arial, sans-serif;
                            background: linear-gradient(135deg, #0f172a, #2563eb, #9333ea);
                            color: white;
                            min-height: 100vh;
                            display: flex;
                            justify-content: center;
                            align-items: center;
                        }

                        .card {
                            background: rgba(255, 255, 255, 0.12);
                            padding: 50px;
                            border-radius: 25px;
                            width: 80%;
                            max-width: 900px;
                            text-align: center;
                            box-shadow: 0 20px 60px rgba(0,0,0,0.35);
                            backdrop-filter: blur(12px);
                        }

                        h1 {
                            font-size: 48px;
                            margin-bottom: 10px;
                        }

                        h2 {
                            color: #fde68a;
                            margin-bottom: 25px;
                        }

                        p {
                            font-size: 20px;
                            line-height: 1.6;
                        }

                        .badges {
                            margin-top: 30px;
                        }

                        .badge {
                            display: inline-block;
                            background: white;
                            color: #1e3a8a;
                            padding: 12px 18px;
                            border-radius: 30px;
                            margin: 8px;
                            font-weight: bold;
                        }

                        .footer {
                            margin-top: 35px;
                            font-size: 16px;
                            color: #e0e7ff;
                        }
                    </style>
                </head>
                <body>
                    <div class="card">
                        <h1>🚀 Utrains DevOps Application</h1>
                        <h2>Java App Successfully Deployed</h2>

                        <p>
                            Welcome to a real Java web application built with Maven.
                            This application can be tested with GitHub Actions, scanned with SonarCloud,
                            scanned with Trivy, packaged as a JAR, and stored in JFrog Artifactory.
                        </p>

                        <div class="badges">
                            <span class="badge">Java 17</span>
                            <span class="badge">Maven</span>
                            <span class="badge">GitHub Actions</span>
                            <span class="badge">SonarCloud</span>
                            <span class="badge">Trivy</span>
                            <span class="badge">JFrog</span>
                        </div>

                        <div class="footer">
                            Built for DevOps CI/CD Practice
                        </div>
                    </div>
                </body>
                </html>
                """;
        });

        get("/health", (req, res) -> {
            res.type("application/json");
            return "{\"status\":\"UP\",\"message\":\"Application is running\"}";
        });
    }
}