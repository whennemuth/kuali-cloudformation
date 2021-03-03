package org.bu.jenkins.active_choices.html;

import java.io.PrintWriter;
import java.io.StringWriter;

/**
 * A simple html conversion of exception message and stack trace.
 * 
 * @author wrh
 *
 */
public class ParameterErrorView implements View {

	private Exception exception;
	
	public ParameterErrorView(Exception exception) {
		this.exception = exception;
	}
	
	@Override
	public String render() {
		StringWriter sw = new StringWriter();
		PrintWriter pw = new PrintWriter(sw);
		pw.write("<pre>");
		pw.write(exception.getMessage());
		pw.write("\n");
		exception.printStackTrace(pw);
		pw.write("</pre>");
		return sw.toString();		
	}
}
