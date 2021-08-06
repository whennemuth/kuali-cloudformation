package org.bu.jenkins.mvc.view;

import java.io.PrintWriter;
import java.io.StringWriter;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.apache.logging.log4j.message.EntryMessage;

/**
 * A simple html conversion of exception message and stack trace.
 * 
 * @author wrh
 *
 */
public class ParameterErrorView implements View {
	
	private Logger logger = LogManager.getLogger(ParameterErrorView.class.getName());

	private Exception exception;
	private String error;
	
	public ParameterErrorView(Object error) {
		if(error instanceof Exception) {
			this.exception = (Exception) error;
		}
		else {
			this.error = error.toString();
		}
	}
	
	@Override
	public String render() {
		if(exception == null) {
			return error;
		}
		EntryMessage m = logger.traceEntry("render()");
		StringWriter sw = new StringWriter();
		PrintWriter pw = new PrintWriter(sw);
		pw.write("<pre>");
		pw.write(exception.getMessage());
		pw.write("\n");
		exception.printStackTrace(pw);
		pw.write("</pre>");
		logger.traceExit(m, sw.getBuffer().length());
		return sw.toString();		
	}
}
