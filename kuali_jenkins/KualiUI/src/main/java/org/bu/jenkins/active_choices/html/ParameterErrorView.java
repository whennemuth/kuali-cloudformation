package org.bu.jenkins.active_choices.html;

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
	
	public ParameterErrorView(Exception exception) {
		this.exception = exception;
	}
	
	@Override
	public String render() {
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
