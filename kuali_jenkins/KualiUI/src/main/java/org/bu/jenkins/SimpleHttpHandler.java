package org.bu.jenkins;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ThreadPoolExecutor;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.message.EntryMessage;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;

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
	
	private Logger logger = LogManager.getLogger(SimpleHttpHandler.class.getName());

	private HttpServer server;
	private ThreadPoolExecutor threadPoolExecutor;
	private static final String CONTEXT = "/active-choices";
	private static final int DEFAULT_PORT = 8001;
	
	public SimpleHttpHandler() {
		super();
		logger.trace("SimpleHttpHandler()");
	}
	
	public abstract String getHtml(Map<String, String> parameters);
	
	@Override
	public void handle(HttpExchange exchange) throws IOException {
		EntryMessage m = logger.traceEntry("handle(exchange.getRequestURI()={}", exchange.getRequestURI().toString());
		Map<String, String> parameters = new HashMap<String, String>(); 
		if("GET".equals(exchange.getRequestMethod())) { 
		   parameters.putAll(handleGetRequest(exchange));
		 }
		else if("POST".equals(exchange.getRequestMethod())) { 
			parameters.putAll(handlePostRequest(exchange));       
		}
		handleResponse(exchange, parameters);
		logger.traceExit(m);
	}

	private Map<String, String> handleGetRequest(HttpExchange exchange) {
		EntryMessage m = logger.traceEntry("handleGetRequest(exchange.getRequestURI()={}", exchange.getRequestURI().toString());
		logger.info("Processing get request: " + exchange.getRequestURI().toString());
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
		logger.traceExit(m);
		return parameters;
	}

	private Map<String, String> handlePostRequest(HttpExchange exchange) {
		EntryMessage m = logger.traceEntry("handlePostRequest(exchange.getRequestURI()={}", exchange.getRequestURI().toString());
		logger.info("Processing post request: " + exchange.getRequestURI().toString());
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

		logger.traceExit(m);
		return map;
	}

	private void handleResponse(HttpExchange exchange, Map<String, String> parameters) {
		EntryMessage m = logger.traceEntry(
				"handleResponse(exchange.getRequestURI()={}, parameters.size()={}", 
				exchange.getRequestURI().toString(), 
				parameters==null ? "null" : parameters.size());
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
		logger.traceExit(m);
	}
	
	public void start() {
		EntryMessage m = logger.traceEntry("start()");
		logger.info("Begin server startup...");
		try {
			if(isWindows()) {
				logger.info("Creating server as 127.0.0.1 on port " + String.valueOf(DEFAULT_PORT));
				// Avoids bind issues, but won't work in a docker container because it does not refer to the bridge network
				server = HttpServer.create(new InetSocketAddress("127.0.0.1", DEFAULT_PORT), 0);
			}
			else {
				logger.info("Creating server on port " + String.valueOf(DEFAULT_PORT));
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
		logger.traceExit(m);
	}
	
	private boolean isWindows() {
		String name = System.getProperty("os.name");
		return name.toLowerCase().contains("window");
	}
	
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
		NamedArgs namedArgs = new NamedArgs(new LoggingStarterImpl(new CaseInsensitiveEnvironment()), args);
		SimpleHttpHandler handler = new SimpleHttpHandler() {
			@Override
			public String getHtml(Map<String, String> map) {
				return "<html><body><h1>Hello world!</h1></body></html>";
			}};
		handler.visitWithBrowser(false);
	}
}

