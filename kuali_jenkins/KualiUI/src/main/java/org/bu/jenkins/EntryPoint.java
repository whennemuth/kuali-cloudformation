package org.bu.jenkins;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import org.bu.jenkins.job.AbstractJob;
import org.bu.jenkins.mvc.controller.kuali.parameter.ParameterController;
import org.bu.jenkins.util.CaseInsensitiveEnvironment;
import org.bu.jenkins.util.NamedArgs;
import org.bu.jenkins.util.logging.LoggingStarterImpl;

public class EntryPoint {

	public static void main(String[] args) throws Exception {
		NamedArgs namedArgs = new NamedArgs(new LoggingStarterImpl(new CaseInsensitiveEnvironment()), args);
		
		if(namedArgs.has("job-class")) {
			args = checkPort(args, 8001);
			AbstractJob.main(args);
		}
		else {
			args = checkPort(args, 8002);
			ParameterController.main(args);
		}
	}
	
	/**
	 * Add the specified port to the args array, but only if the array does not already have a port entry.
	 *  
	 * @param args
	 * @param defaultPort
	 * @return
	 */
	private static String[] checkPort(String[] args, Integer defaultPort) {
		NamedArgs namedArgs = new NamedArgs(new LoggingStarterImpl(new CaseInsensitiveEnvironment()), args);
		if(namedArgs.getInt("port") == null) {
			List<String> arglist = new ArrayList<String>(Arrays.asList(args));
			arglist.add("port=" + String.valueOf(defaultPort));
			return arglist.toArray(new String[arglist.size()]);
		}
		return args;
	}
}
