package org.bu.jenkins.cli;

import java.io.File;
import java.util.List;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import org.bu.jenkins.active_choices.dao.AbstractGitDAO;
import org.bu.jenkins.util.Path;

/**
 * Git utility class that acts as an adapter for direct command line use of git.
 * Output from git commands made on the system command line are parsed and returned as a list.
 * Access can be provided by specifying either an SSH key or user and personal access token combination.
 *  
 * @author wrh
 *
 */
public abstract class GitCommandLineAdapter extends AbstractGitDAO {
	
	Logger logger = LogManager.getLogger(GitCommandLineAdapter.class.getName());

	protected RuntimeCommand cmd;
	protected String remoteUrl;
	protected String refValue;
	
	private File sshKey;
	private String user;
	private String personalAccessToken;
	private String scriptDir;
	private Boolean dryrun = false;

	public GitCommandLineAdapter(RuntimeCommand cmd) {
		this.cmd = cmd;
	}
	
	public abstract String getGitCommand();
	
	public abstract List<String> getFilteredOutput();
	
	protected String printGitOutput(RefType refType) {
		
		if(validParms()) {
			
			buildRemoteUrl();
			
			String gitcmd = getGitCommand();
			
			if( ! useToken() ) {		
				String keyPathStr = new Path(sshKey.getAbsolutePath()).toLinux(cmd.isWSL());
				cmd.setScriptFile(new File(getScriptDir() + File.separator + "utils.sh"));
				
				cmd.setArgs(keyPathStr, gitcmd);				
			}
			else {
				cmd.setArgs(gitcmd);
			}

			logger.info(gitcmd);
			
			if(dryrun) {
				return null;
			}
			
			if(cmd.run()) {
				if(cmd.hasError()) {
					return cmd.getErrorOutput();
				}
				else {
					return cmd.getOutput();
				}
			}
			else {
				logger.error("Process for acquiring git tags failed!");
				return null;
			}
		}
		else {
			logger.error("Invalid or missing parms for tag lookup!");
			return null;
		}
	}
	
	/**
	 * A certain amount of default parts of a full github remote url can be inferred, depending on what 
	 * is the field was originally set with and whether or not that value looks like shorthand. This function
	 * changes any shorthand to the full url.
	 * 
	 * Example of full url with personal access token:
	 *   "https://git_user:git_user_personal_access_token@github.com/bu-ist/kuali-core-main.git"
	 * 
	 * Example of full url with ssh key:
	 *   "git@github.com:bu-ist/kuali-research-coi.git"
	 */
	private void buildRemoteUrl() {
		if(remoteUrl.contains("github.com")) {
			remoteUrl = remoteUrl.split("github\\.com[/:]")[1];
		}
		if(useToken()) {
			remoteUrl = String.format("https://%s:%s@github.com/%s", user, personalAccessToken, remoteUrl);
		}
		else if(useSshKey()) {
			remoteUrl = "git@github.com:" + remoteUrl;
		}
		if( ! remoteUrl.endsWith(".git")) {
			remoteUrl = remoteUrl + ".git";
		}
	}
	
	@Override
	public List<String> getOutputList() {
		return getFilteredOutput();
	}
	
	public String getOutput() {
		List<String> outputs = getOutputList();
		if(outputs == null || outputs.isEmpty()) {
			return null;
		}
		return outputs.get(0);
	}
	
	public boolean hasError() {
		if(cmd == null) {
			return false;
		}
		return cmd.hasError();
	}
	
	public String getErrorOutput() {
		if(cmd != null) {
			return cmd.getErrorOutput();
		}
		return null;
	}

	private static boolean isMissing(Object o) {
		if(o == null || o.toString().isBlank()) return true;
		return false;
	}
	
	private boolean useToken() {
		if(isMissing(user)) return false;
		if(isMissing(personalAccessToken)) return false;
		if(isMissing(remoteUrl)) return false;
		return true;
	}
	
	private boolean useSshKey() {
		if(sshKey == null || ! sshKey.isFile()) return false;
		if(isMissing(remoteUrl)) return false;
		return true;
	}
	
	private boolean validParms() {
		if(useSshKey() || useToken()) return true;
		return false;
	}
	
	public File getSshKey() {
		return sshKey;
	}
	public GitCommandLineAdapter setSshKey(File sshKey) {
		this.sshKey = sshKey;
		return this;
	}
	public String getPersonalAccessToken() {
		return personalAccessToken;
	}
	public GitCommandLineAdapter setPersonalAccessToken(String personalAccessToken) {
		this.personalAccessToken = personalAccessToken;
		return this;
	}
	public GitCommandLineAdapter setSshKeyPath(String sshKeyPath) {
		this.sshKey = new File(sshKeyPath);
		return this;
	}
	public String getRemoteUrl() {
		return remoteUrl;
	}
	public GitCommandLineAdapter setRemoteUrl(String remoteUrl) {
		this.remoteUrl = remoteUrl;
		return this;
	}	
	public String getUser() {
		return user;
	}
	public GitCommandLineAdapter setUser(String user) {
		this.user = user;
		return this;
	}
	public String getScriptDir() {
		if(scriptDir == null || ! new File(scriptDir).isDirectory()) {
			return System.getProperty("user.dir"); // Assume windows
		}
		return scriptDir;
	}
	public GitCommandLineAdapter setScriptDir(String scriptDir) {
		this.scriptDir = scriptDir;
		return this;
	}
	protected AbstractGitDAO setDryrun(Boolean dryrun) {
		this.dryrun = dryrun;
		return this;
	}
	public void setRefValue(String refValue) {
		this.refValue = refValue;
	}
	public String getRefValue() {
		return refValue;
	}
	
}
