package org.bu.jenkins.dao.cli;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

/**
 * For unknown reasons, the Process.waitFor() and Process.exitValue() methods cause some kind of block in the
 * underlying process and withholding of an exit code when the output of the process is over a certain size. 
 * This happens when bash.exe is executing a script file (does not happen with inline code, ie: bash -c "some code"). 
 * Therefore the OutputStream.ready() states of the process standard and error output streams are monitored 
 * instead to determine if the process output can be consumed. This is most likely a windows only issue.
 * 
 * @author wrh
 *
 */
public abstract class WaitFor {
	
	private Logger logger = LogManager.getLogger(WaitFor.class.getName());
	
	private int mils;
	private int max;
	private int sum;
	
	public WaitFor() {
		this(10000, 50);
	}
	
	public WaitFor(int max) {
		this(max, 50);
	}
	
	public WaitFor(int max, int mils) {
		this.max = max;
		this.mils = mils;
	}

	public abstract void onComplete(int sum) throws Exception;
	
	public abstract void onTimeout(int max) throws Exception;
	
	public abstract boolean isReady() throws Exception;
	
	public void await() throws Exception {
		while( ! isReady() && ! timeout()) {
			try {
				Thread.sleep(mils);
			} 
			catch (InterruptedException e) {
				logger.error(e.getMessage());
			}
			sum += mils;
		}
		
		if(timeout()) {
			onTimeout(max);
		}
		else {
			onComplete(sum);
		}
	}
	
	private boolean timeout() {
		return sum >= max;
	}
}
