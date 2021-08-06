package org.bu.jenkins.dao.cli;

import java.io.BufferedOutputStream;
import java.io.BufferedReader;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.PrintWriter;
import java.io.StringReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.bu.jenkins.util.CaseInsensitiveEnvironment;
import org.bu.jenkins.util.NamedArgs;
import org.bu.jenkins.util.Path;
import org.bu.jenkins.util.logging.LoggingStarterImpl;

/**
 * This class uses the java ProcessBuilder and Process classes to run and stream the output of a provided string
 * command that could otherwise be used on the system command line. If the output stream is a ByteArrayOutputStream, 
 * then it can be returned by an accessor of this object as a string.
 * @author wrh
 *
 */
public class RuntimeCommand {

	private File scriptFile;
	private String scriptEngine = "bash"; // maybe sh, but some things don't work.
	private List<String> args = new ArrayList<String>();
	private Integer exitValue;
	private OutputStream os;
	private PrintWriter pw;
	
	private StringBuilder err = new StringBuilder();
	
	private Logger logger = LogManager.getLogger(RuntimeCommand.class.getName());
			
	public RuntimeCommand setArgs(String...command) {
		args.clear();
		args.addAll(Arrays.asList(command));
		return this;
	}
	
	public RuntimeCommand prependArg(String arg) {
		args.add(0, arg);
		return this;
	}
	
	/**
	 * Get the array of command parts, which are: shell, switch & args (command + args, or script file + args)
	 */
	private String[] getCommand(boolean asString) {
		List<String> cmdlist = new ArrayList<String>();
		if(getScriptFile().isFile()) {
			cmdlist.add(scriptEngine);
			cmdlist.add(new Path(scriptFile.getAbsolutePath()).toLinux(isWSL()));
			cmdlist.addAll(args);		
		}
		else if(asString) {
			cmdlist.add(scriptEngine);
			cmdlist.add(isWindowsCmd() ? "/c" : "-c");
			cmdlist.add(String.join(" ", args.toArray(new String[args.size()])));			
		}
		else {
			cmdlist.addAll(args);			
		}
		
		logger.debug("Command: ");
		for(String cmd : cmdlist) {
			logger.debug("    " + cmd);
		}
		return cmdlist.toArray(new String[cmdlist.size()]);
	}
	
	public boolean isWSL() {
		return "bash".equals(scriptEngine) && Path.isWindows;
	}
	
	public RuntimeCommand setOutputStream(OutputStream os) {
		this.os = os;
		initializeOutputStreams();
		return this;
	}
	
	public RuntimeCommand setScriptFile(File scriptFile) {
		this.scriptFile = scriptFile;
		return this;
	}
	
	public File getScriptFile() {
		if(scriptFile == null) {
			return new File("");
		}
		return scriptFile;
	}
	
	public boolean isWindowsCmd() {
		if(Path.isWindows) {
			if("cmd.exe".equalsIgnoreCase(scriptEngine)) {
				return true;
			}
			if(getScriptFile().getName().toLowerCase().endsWith(".bat")) {
				return true;
			}
		}
		return false;
	}

	public RuntimeCommand setScriptFilePath(String absolutePath) {
		this.scriptFile = new File(absolutePath);
		return this;
	}
	
	public String getScriptEngine() {
		return scriptEngine;
	}

	public RuntimeCommand setScriptEngine(String scriptEngine) {
		this.scriptEngine = scriptEngine;
		return this;
	}

	private void initializeOutputStreams() {
		this.os = new ByteArrayOutputStream();
		this.pw = new PrintWriter(new BufferedOutputStream(this.os));
	}
	
	public boolean run() {
		return run(getScriptFile().isFile());
	}
	
	public boolean runAsString() {
		return run(true);
	}

	/**
	 * Invoke the process with the provided command with the output directed to an output stream.
	 * If the output stream is a ByteArrayOutputStream, then it can be returned by an accessor of this object as a string.
	 * @return
	 */
	private boolean run(boolean asString)  {
		
		initializeOutputStreams();
		
		ProcessBuilder builder = null;
		Process process = null;
		final BufferedReader reader;
		final BufferedReader errReader;
		
		try {
			
			builder = new ProcessBuilder();
			builder.command(getCommand(asString));
			
			process = builder.start();
			reader = new BufferedReader(new InputStreamReader(process.getInputStream()));
			errReader = new BufferedReader(new InputStreamReader(process.getErrorStream()));
			
			// process.waitFor(); // This will block the process from sending an exit code. SEE WaitFor
			WaitFor waiter = new WaitFor() {

				@Override public void onComplete(int sum) throws Exception {
					logger.debug(String.format("Process output stream ready after %s milliseconds.", sum));
		            String line = "";
		            
					try {
						while (reader.ready()) {
						    line = reader.readLine();
						    if(line == null) {
						    	break;
						    }
						    pw.println(line);
						}
						
						while (errReader.ready()) {
						    line = errReader.readLine();
						    if(line == null) {
						    	break;
						    }
						    err.append(line);
						}
					} 
					finally {
						try {
							if(reader != null) {
								reader.close();
							}
						} 
						catch (IOException e) {
							logger.error(e.getMessage(), e);
						}
						try {
							if(errReader != null) {
								errReader.close();
							}
						} 
						catch (IOException e) {
							logger.error(e.getMessage(), e);
						}
					}				
				}

				@Override public void onTimeout(int max) throws Exception {
					logger.error(String.format("Process output streams remain unready beyond %s millisecond timeout!", max));
				}

				@Override public boolean isReady() throws Exception {
					return reader.ready() || errReader.ready();
				}				
			};
			
			waiter.await();

			pw.flush();
		}
		catch (Exception e) {
			logger.error(e.getMessage(), e);
			return false;
		}
		finally {
			if(process != null && process.isAlive()) {
				process.destroy();
			}
		}
		
		return true;
	}
	
	/**
	 * Indicate if any stderr was output by the process
	 * @return
	 */
	public boolean hasError() {
		return err.length() > 0;
	}
	
	/**
	 * Get any output issued on stderr by the process.
	 * @return
	 */
	public String getErrorOutput() {
		return err.toString();
	}
	
	/**
	 * Return the output of the process as a string.
	 * @return
	 */
	public String getOutput() {
		if(os instanceof ByteArrayOutputStream) {
			return new String(((ByteArrayOutputStream) os).toByteArray());
		}
		else {
			return "Empty!";
		}
	}
	
	/**
	 * Get the multi-line process output, but return it as a list, one item for each line.
	 * @return
	 */
	public List<String> getOutputList() {
		BufferedReader bf = new BufferedReader(new StringReader(getOutput()));
		List<String> images = new ArrayList<String>();
		String image = null;
		try {
			while((image = bf.readLine()) != null) {				
				images.add(image);
			}
			return images;
		} 
		catch (IOException e) {
			logger.error(e.getMessage(), e);
			return images;
		}		
	}
	
	/**
	 * Return the exit value of the string.
	 * @return
	 */
	public int getExitValue() {
		return exitValue;
	}

	/**
	 * Combine two arrays into one.
	 * @param <T>
	 * @param array1
	 * @param array2
	 * @return
	 */
	public static <T> T[] concatArrays(T[] array1, T[] array2) {
	    T[] result = Arrays.copyOf(array1, array1.length + array2.length);
	    System.arraycopy(array2, 0, result, array1.length, array2.length);
	    return result;
	}
	
	public static RuntimeCommand getScriptInstance(OutputStream os, File scriptfile, String...args) {
		if(scriptfile.isFile()) {
			return new RuntimeCommand()
					.setScriptFile(scriptfile)
					.setArgs(args)
					.setOutputStream(os);
		}
		else {
			String errmsg = "\"No such script file: " + String.valueOf(scriptfile) + "\"";
			return new RuntimeCommand().setArgs(new String[] { "echo", errmsg });
		}		
	}
	
	public static RuntimeCommand getScriptInstance(File scriptfile, String...args) {
		return getScriptInstance(null, scriptfile);
	}
	
	public static RuntimeCommand getCommandInstance(OutputStream os, String...command) {
		return new RuntimeCommand()
				.setArgs(command)
				.setOutputStream(os);
	}
	
	public static RuntimeCommand getCommandInstance(String...command) {
		return getCommandInstance(null, command);
	}

	public static void main(String[] args) throws IOException {
		@SuppressWarnings("unused")
		NamedArgs namedArgs = new NamedArgs(new LoggingStarterImpl(new CaseInsensitiveEnvironment()), args);
		
		RuntimeCommand rc = null;

		rc = getCommandInstance(System.out, "git", "--version");		
		rc.run();		
		if(rc.hasError()) {
			System.err.println(rc.getErrorOutput());
		}
		else {
			System.out.println(rc.getOutput());
		}

		rc = getCommandInstance(System.out, "echo", "This is test two!");		
		rc.runAsString();	
		if(rc.hasError()) {
			System.err.println(rc.getErrorOutput());
		}
		else {
			System.out.println(rc.getOutput());
		}
		
		rc = getCommandInstance("git", "--version");
		rc.run();		
		if(rc.hasError()) {
			System.err.println(rc.getErrorOutput());
		}
		else {
			System.out.println(rc.getOutput());
		}
		
		File test = File.createTempFile("test", ".bat");
		test.deleteOnExit();
		PrintWriter pw = new PrintWriter(new FileWriter(test));
		pw.println("@ECHO OFF");
		pw.println("echo This is test four (a);");
		pw.println("echo This is test four (b);");
		pw.println("echo This is test four (c);");
		pw.flush();
		pw.close();
		rc = getScriptInstance(System.out, test);
		rc.setScriptEngine("cmd.exe");
		rc.run();		
		if(rc.hasError()) {
			System.err.println(rc.getErrorOutput());
		}
		else {
			System.out.println(rc.getOutput());
		}
	}
}
