package org.bu.jenkins;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.UnsupportedEncodingException;
import java.net.InetSocketAddress;
import java.util.HashMap;
import java.util.Map;
import java.util.Map.Entry;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadPoolExecutor;

import com.sun.net.httpserver.*;

/**
 * A simple http server that impersonates the dynamic active choices plugin behavior in a jenkins job.
 * Active choices operates with a subscriber pattern where changes in the value of one parameter cause
 * automatic refreshes to other active choices parameter displays. This is done in response to onblur 
 * and onchange triggering events. This handler simulates the triggered refreshes through form submissions.
 * 
 * @author wrh
 *
 */
@SuppressWarnings("restriction")
public abstract class SimpleHttpHandler implements HttpHandler {

	private HttpServer server;
	private ThreadPoolExecutor threadPoolExecutor;
	private static final String CONTEXT = "/active-choices";
	private static final int DEFAULT_PORT = 8001;
	
	public SimpleHttpHandler() {
		super();
	}
	
	public abstract String getHtml(Map<String, String> parameters);
	
	@SuppressWarnings("restriction")
	@Override
	public void handle(HttpExchange exchange) throws IOException {
		Map<String, String> parameters = new HashMap<String, String>(); 
		if("GET".equals(exchange.getRequestMethod())) { 
		   parameters.putAll(handleGetRequest(exchange));
		 }
		else if("POST".equals(exchange.getRequestMethod())) { 
			parameters.putAll(handlePostRequest(exchange));       
		}
		handleResponse(exchange, parameters); 
	}

	@SuppressWarnings("restriction")
	private Map<String, String> handleGetRequest(HttpExchange exchange) {
		System.out.println("Processing get request: " + exchange.getRequestURI().toString());
		String[] parts = exchange.getRequestURI().toString().split("\\?");
		Map<String, String> parameters = new HashMap<String, String>();
		if(parts.length == 2) {
			String[] pairs = parts[1].split("&"); 
			for(String pairStr : pairs) {
				String[] pair = pairStr.split("=");
				if(pair.length == 2) {
					parameters.put(pair[0], pair[1]);
				}
			}
		}
		return parameters;
	}

	@SuppressWarnings("restriction")
	private Map<String, String> handlePostRequest(HttpExchange exchange) {
		Map<String, String> map = new HashMap<String, String>();
        Map<String, Object> parameters = (Map<String, Object>) exchange.getAttribute("parameters");
        InputStreamReader isr = null;
		try {
			isr = new InputStreamReader(exchange.getRequestBody(),"utf-8");
            BufferedReader br = new BufferedReader(isr);
            String query = br.readLine();
            while(query != null) {
            	System.out.println(query);
            	query = br.readLine();
            	// TODO: write code to parse posted form data.
            }            
		} 
		catch (Exception e) {
			e.printStackTrace();
		}

		return map;
	}

	@SuppressWarnings("restriction")
	private void handleResponse(HttpExchange exchange, Map<String, String> parameters) {
		OutputStream outputStream = exchange.getResponseBody();
		try {
			String html = getHtml(parameters);
			exchange.sendResponseHeaders(200, html.length());
			outputStream.write(html.getBytes());
			outputStream.flush();
			outputStream.close();
		} 
		catch (IOException e) {
			e.printStackTrace(System.out);
		}
	}
	
	public void start() {
		System.out.println("Begin server startup...");
		try {
			if(isWindows()) {
				System.out.println("Creating server as 127.0.0.1 on port " + String.valueOf(DEFAULT_PORT));
				// Avoids bind issues, but won't work in a docker container because it does not refer to the bridge network
				server = HttpServer.create(new InetSocketAddress("127.0.0.1", DEFAULT_PORT), 0);
			}
			else {
				System.out.println("Creating server on port " + String.valueOf(DEFAULT_PORT));
				server = HttpServer.create(new InetSocketAddress(DEFAULT_PORT), 0);
			}
			server.createContext(CONTEXT, this);
			threadPoolExecutor = (ThreadPoolExecutor)Executors.newFixedThreadPool(10);
			server.setExecutor(threadPoolExecutor);
			server.start();
		} 
		catch (IOException e) {
			e.printStackTrace(System.out);
		}		
		
	}
	
	private boolean isWindows() {
		String name = System.getProperty("os.name");
		return name.toLowerCase().contains("window");
	}
	
	@SuppressWarnings("restriction")
	public void visitWithBrowser(boolean keepRunning) {
		try {
			start();
			Runtime.getRuntime().exec(new String[]{"cmd", "/c", "start chrome http://127.0.0.1:" + String.valueOf(DEFAULT_PORT) + CONTEXT});
			if( ! keepRunning) {
				Thread.sleep(2000);
				server.stop(5);
				threadPoolExecutor.shutdown();
			}
		} 
		catch (IOException | InterruptedException e) {
			e.printStackTrace(System.out);
		}		
	}

	public static void main(String[] args) {
		NamedArgs namedArgs = new NamedArgs(args);
		SimpleHttpHandler handler = new SimpleHttpHandler() {
			@Override
			public String getHtml(Map<String, String> map) {
				return "<html><body><h1>Hello world!</h1></body></html>";
			}};
		handler.visitWithBrowser(false);
	}
}

