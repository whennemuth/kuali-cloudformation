package org.bu.jenkins.cli;

import java.util.List;

import org.bu.jenkins.util.CaseInsensitiveEnvironment;
import org.bu.jenkins.util.NamedArgs;
import org.bu.jenkins.util.StringToList;
import org.bu.jenkins.util.logging.LoggingStarterImpl;

/**
 * Uses the system command line to make a git call for a particular commit id 
 * for the specified tag or the head of the specified branch.
 * 
 * @author wrh
 *
 */
public class GitCommits extends GitCommandLineAdapter {

	public GitCommits(RuntimeCommand cmd) {
		super(cmd);
	}

	@Override
	public String getGitCommand() {
		
		return String.format(
				"git -c core.askpass=true ls-remote -%s %s refs/%s/ %s",
				refType.categorySwitch(),
				remoteUrl,
				refType.category(),
				refValue);
	}

	@Override
	public List<String> getFilteredOutput() {
		final String category = String.format("refs/%s/", refType.category());
		return new StringToList(printGitOutput(refType)) {
			@Override public String filter(String ref) {
				if(ref.contains(category)) {
					return ref.split(category)[0].strip();
				}
				else if(cmd.hasError()) {
					return ref;
				}
				return null;
			}
		}.getList();
	}

	public static void main(String[] args) {
		NamedArgs namedargs = new NamedArgs(new LoggingStarterImpl(new CaseInsensitiveEnvironment()), args);
		
		GitCommits commits = new GitCommits(RuntimeCommand.getCommandInstance());
		
		commits.setRefType(RefType.BRANCH);
		commits.setRefValue(namedargs.get("git-branch-ref", "master"));
		commits.setSshKeyPath(namedargs.get("ssh-key", "C:\\Users\\wrh\\.ssh\\bu_github_id_coi_rsa"));
		commits.setPersonalAccessToken(namedargs.get("pat"));
		commits.setRemoteUrl(namedargs.get("remote-url", "git@github.com:bu-ist/kuali-research-coi.git"));
		commits.setUser(namedargs.get("user", "bu-ist-user"));
		commits.setDryrun(Boolean.valueOf(namedargs.get("dryrun", "false")));

		System.out.println(commits.getRefValue() + ": " + commits.getOutput());
		
		commits.setRefType(RefType.TAG);
		commits.setRefValue(namedargs.get("git-tag-ref", "1908.0023"));

		System.out.println(commits.getRefValue() + ": " + commits.getOutput());
		
	}
}
